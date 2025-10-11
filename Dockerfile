#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telegram Group Moderator Bot - Advanced Version
Features:
- Silent moderation (no responses except admin promotions)
- Phone number detection and deletion
- Edit tracking and deletion
- Developer-controlled admin promotion system
- Intelligent message filtering
"""

import re
import asyncio
import sqlite3
import os
import logging
from datetime import datetime, timezone
from typing import Optional, Set, Dict, Any
from dataclasses import dataclass
from contextlib import asynccontextmanager
from io import BytesIO

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ChatPermissions, InputFile
from telegram.helpers import escape_markdown
from telegram.ext import (
    ApplicationBuilder, 
    ContextTypes, 
    MessageHandler, 
    CommandHandler, 
    CallbackQueryHandler,
    filters
)
from telegram.constants import ChatMemberStatus
import random
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prevent token leakage in HTTP logs
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("telegram").setLevel(logging.WARNING)

# ---------- Configuration ----------
TOKEN = ("7008028219:AAGxu-uvfPfFiMlEh1wIgMAY_wExd__rgWs")
if not TOKEN:
    raise ValueError("TG_BOT_TOKEN environment variable is required")

# Developer ID - the only one who can promote admins
DEVELOPER_ID = 55265877

# Global owners - can promote/demote across all groups
GLOBAL_OWNERS = {55265877}  # Add more global owner IDs as needed

# Super admins who can change developer
SUPER_ADMINS = {55265877, 504602287}

@dataclass
class BotConfig:
    """Bot configuration class"""
    edit_window_seconds: int = 5  # 5 seconds edit window
    silent_mode: bool = False  # Allow funny responses
    media_delete_minutes: int = 2  # Delete media after 2 minutes

config = BotConfig()

# Funny responses in Arabic
FUNNY_RESPONSES = [
    "😂 هههههههه",
    "🤣 ضحكتني والله",
    "😄 حلوة هذي",
    "🙃 طيب يا كوميدي",
    "😆 أنت مضحك فعلاً",
    "🤪 ما شاء الله عليك",
    "😁 تسلم يا فنان",
    "🤨 هذا كل اللي عندك؟",
    "😏 شطور",
    "🫡 احترمناك",
    "🤓 عبقري",
    "🫠 ولا بلاش",
    "😎 كفو",
    "🤔 مثير للاهتمام",
    "😑 تمام"
]

# Comprehensive phone number patterns (international and Arabic)
PHONE_PATTERNS = [
    # International formats
    re.compile(r'\+?[1-9]\d{1,14}'),  # E.164 format
    re.compile(r'\(?\d{3}\)?[-\s]?\d{3}[-\s]?\d{4}'),  # US format
    re.compile(r'\d{2,4}[-\s]?\d{3,4}[-\s]?\d{3,4}'),  # General format
    re.compile(r'\b\d{10,15}\b'),  # 10-15 digit sequences

    # Arabic numerals
    re.compile(r'[٠-٩]{2,}[-\s]*[٠-٩]{2,}[-\s]*[٠-٩]{2,}'),
    re.compile(r'\+?[٠-٩]{8,15}'),

    # Mixed formats
    re.compile(r'[0-9٠-٩]{3,}[-\s\(\)]*[0-9٠-٩]{3,}[-\s\(\)]*[0-9٠-٩]{3,}'),

    # Country code patterns
    re.compile(r'\+?(966|971|965|973|974|968|962|961|20|213|212)[-\s]?[0-9٠-٩]{7,9}'),  # Arab countries
    re.compile(r'\+?1[-\s]?[0-9]{10}'),  # US/Canada
    re.compile(r'\+?44[-\s]?[0-9]{10}'),  # UK

    # WhatsApp/Telegram contact patterns
    re.compile(r'wa\.me/[0-9+]{8,15}', re.IGNORECASE),
    re.compile(r't\.me/[0-9+]{8,15}', re.IGNORECASE),
]

# Enhanced banned content patterns
BANNED_KEYWORDS = [
    "kill", "murder", "shoot", "suicide", "bomb", "terrorist", "terrorism",
    "i will kill you", "die", "attack", "assault", "beat you", "rape", "abuse", "torture",
    "threat", "hurt you", "slaughter", "child abuse", "pedophilia", "cp", "child pornography",
    "sexual assault", "pron", "incest", "underage", "nude", "minor", "exploitation", "drugs",
    "cocaine", "heroin", "racist", "nazi", "isis", "al-qaeda", "kkk", "extremist", "hate speech",
    "genocide", "hack", "scam", "spam", "fraud", "phishing", "credit card scam", "identity theft",
]

# Link detection patterns
LINK_PATTERNS = [
    re.compile(r'https?://[^\s]+', re.IGNORECASE),
    re.compile(r't\.me/[^\s]+', re.IGNORECASE),
    re.compile(r'telegram\.me/[^\s]+', re.IGNORECASE),
    re.compile(r'www\.[^\s]+', re.IGNORECASE),
    re.compile(r'[a-zA-Z0-9-]+\.[a-z]{2,}/[^\s]*', re.IGNORECASE),
]

# Credit card patterns
CREDIT_CARD_PATTERNS = [
    re.compile(r'\b4[0-9]{12}(?:[0-9]{3})?\b'),  # Visa
    re.compile(r'\b5[1-5][0-9]{14}\b'),  # MasterCard
    re.compile(r'\b3[47][0-9]{13}\b'),  # American Express
    re.compile(r'\b6(?:011|5[0-9]{2})[0-9]{12}\b'),  # Discover
    re.compile(r'\b[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}\b'),  # Generic format
]

# Arabic text detection
ARABIC_PATTERN = re.compile(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]')

# ---------- Database Management ----------
class DatabaseManager:
    """Advanced database management with connection pooling and error handling"""

    def __init__(self, db_file: str = "advanced_moderator.db"):
        self.db_file = db_file
        self.init_database()

    def init_database(self):
        """Initialize database with proper schema"""
        try:
            with sqlite3.connect(self.db_file) as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS trusted_users (
                        chat_id INTEGER,
                        user_id INTEGER,
                        promoted_by INTEGER,
                        promoted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        PRIMARY KEY(chat_id, user_id)
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS message_log (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        chat_id INTEGER,
                        user_id INTEGER,
                        message_id INTEGER,
                        action TEXT,
                        reason TEXT,
                        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS user_warnings (
                        chat_id INTEGER,
                        user_id INTEGER,
                        warning_count INTEGER DEFAULT 0,
                        last_warning TIMESTAMP,
                        PRIMARY KEY(chat_id, user_id)
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS muted_users (
                        chat_id INTEGER,
                        user_id INTEGER,
                        muted_by INTEGER,
                        muted_until TIMESTAMP,
                        reason TEXT,
                        message_id INTEGER,
                        PRIMARY KEY(chat_id, user_id)
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS global_owners (
                        user_id INTEGER PRIMARY KEY,
                        promoted_by INTEGER,
                        promoted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS user_registrations (
                        user_id INTEGER PRIMARY KEY,
                        username TEXT,
                        full_name TEXT,
                        registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                conn.execute("""
                    CREATE TABLE IF NOT EXISTS developer_changes (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        old_developer INTEGER,
                        new_developer INTEGER,
                        changed_by INTEGER,
                        changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS admin_permissions (
                        chat_id INTEGER,
                        user_id INTEGER,
                        can_delete_messages INTEGER DEFAULT 0,
                        can_restrict_members INTEGER DEFAULT 0,
                        can_promote_members INTEGER DEFAULT 0,
                        can_change_info INTEGER DEFAULT 0,
                        can_invite_users INTEGER DEFAULT 0,
                        can_pin_messages INTEGER DEFAULT 0,
                        can_manage_chat INTEGER DEFAULT 0,
                        PRIMARY KEY(chat_id, user_id)
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS bot_promoted_admins (
                        chat_id INTEGER,
                        user_id INTEGER,
                        promoted_by INTEGER,
                        promoted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        can_manage_voice_chats INTEGER DEFAULT 0,
                        PRIMARY KEY(chat_id, user_id)
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS full_protection (
                        chat_id INTEGER PRIMARY KEY,
                        enabled INTEGER DEFAULT 0,
                        enabled_by INTEGER,
                        enabled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS whispers (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        chat_id INTEGER,
                        from_user_id INTEGER,
                        to_user_id INTEGER,
                        message TEXT,
                        seen INTEGER DEFAULT 0,
                        group_message_id INTEGER,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                conn.commit()
                logger.info("Database initialized successfully")
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")
            raise

    @asynccontextmanager
    async def get_connection(self):
        """Async context manager for database connections"""
        conn = None
        try:
            conn = sqlite3.connect(self.db_file)
            conn.row_factory = sqlite3.Row
            yield conn
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Database operation failed: {e}")
            raise
        finally:
            if conn:
                conn.close()

    async def add_trusted_user(self, chat_id: int, user_id: int, promoted_by: int):
        """Add user to trusted list"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO trusted_users (chat_id, user_id, promoted_by) VALUES (?, ?, ?)",
                (chat_id, user_id, promoted_by)
            )
            conn.commit()

    async def is_trusted(self, chat_id: int, user_id: int) -> bool:
        """Check if user is trusted"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT 1 FROM trusted_users WHERE chat_id=? AND user_id=? LIMIT 1",
                (chat_id, user_id)
            )
            return bool(cursor.fetchone())

    async def log_action(self, chat_id: int, user_id: int, message_id: int, action: str, reason: str):
        """Log moderation actions"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT INTO message_log (chat_id, user_id, message_id, action, reason) VALUES (?, ?, ?, ?, ?)",
                (chat_id, user_id, message_id, action, reason)
            )
            conn.commit()

    async def mute_user(self, chat_id: int, user_id: int, muted_by: int, duration_minutes: int, reason: str, message_id: int = None):
        """Mute user for specified duration"""
        from datetime import datetime, timedelta, timezone
        muted_until = datetime.now(timezone.utc) + timedelta(minutes=duration_minutes)
        
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO muted_users (chat_id, user_id, muted_by, muted_until, reason, message_id) VALUES (?, ?, ?, ?, ?, ?)",
                (chat_id, user_id, muted_by, muted_until, reason, message_id)
            )
            conn.commit()

    async def unmute_user(self, chat_id: int, user_id: int):
        """Remove user from muted list"""
        async with self.get_connection() as conn:
            conn.execute(
                "DELETE FROM muted_users WHERE chat_id=? AND user_id=?",
                (chat_id, user_id)
            )
            conn.commit()

    async def is_user_muted(self, chat_id: int, user_id: int) -> bool:
        """Check if user is currently muted"""
        from datetime import datetime, timezone
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT muted_until FROM muted_users WHERE chat_id=? AND user_id=? AND muted_until > ?",
                (chat_id, user_id, datetime.now(timezone.utc))
            )
            return bool(cursor.fetchone())

    async def add_warning(self, chat_id: int, user_id: int) -> int:
        """Add warning to user and return total warning count"""
        from datetime import datetime, timezone
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT warning_count FROM user_warnings WHERE chat_id=? AND user_id=?",
                (chat_id, user_id)
            )
            row = cursor.fetchone()
            
            if row:
                new_count = row[0] + 1
                conn.execute(
                    "UPDATE user_warnings SET warning_count=?, last_warning=? WHERE chat_id=? AND user_id=?",
                    (new_count, datetime.now(timezone.utc), chat_id, user_id)
                )
            else:
                new_count = 1
                conn.execute(
                    "INSERT INTO user_warnings (chat_id, user_id, warning_count, last_warning) VALUES (?, ?, ?, ?)",
                    (chat_id, user_id, new_count, datetime.now(timezone.utc))
                )
            
            conn.commit()
            return new_count

    async def get_warning_count(self, chat_id: int, user_id: int) -> int:
        """Get user's warning count"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT warning_count FROM user_warnings WHERE chat_id=? AND user_id=?",
                (chat_id, user_id)
            )
            row = cursor.fetchone()
            return row[0] if row else 0

    async def reset_warnings(self, chat_id: int, user_id: int):
        """Reset user's warnings"""
        async with self.get_connection() as conn:
            conn.execute(
                "DELETE FROM user_warnings WHERE chat_id=? AND user_id=?",
                (chat_id, user_id)
            )
            conn.commit()

    async def add_global_owner(self, user_id: int, promoted_by: int):
        """Add user to global owners"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO global_owners (user_id, promoted_by) VALUES (?, ?)",
                (user_id, promoted_by)
            )
            conn.commit()

    async def is_global_owner(self, user_id: int) -> bool:
        """Check if user is a global owner"""
        return user_id in GLOBAL_OWNERS or await self._is_db_global_owner(user_id)

    async def _is_db_global_owner(self, user_id: int) -> bool:
        """Check if user is global owner in database"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT 1 FROM global_owners WHERE user_id=? LIMIT 1",
                (user_id,)
            )
            return bool(cursor.fetchone())

    async def get_admins_list(self, chat_id: int) -> list:
        """Get list of trusted users (admins) in chat"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT user_id, promoted_by, promoted_at FROM trusted_users WHERE chat_id=?",
                (chat_id,)
            )
            return cursor.fetchall()

    async def register_user(self, user_id: int, username: str = None, full_name: str = None):
        """Register new user"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO user_registrations (user_id, username, full_name) VALUES (?, ?, ?)",
                (user_id, username, full_name)
            )
            conn.commit()

    async def get_global_owners_list(self) -> list:
        """Get list of global owners"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT user_id, promoted_by, promoted_at FROM global_owners"
            )
            return cursor.fetchall()

    async def log_developer_change(self, old_dev: int, new_dev: int, changed_by: int):
        """Log developer change"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT INTO developer_changes (old_developer, new_developer, changed_by) VALUES (?, ?, ?)",
                (old_dev, new_dev, changed_by)
            )
            conn.commit()
    
    async def get_users_count(self) -> int:
        """Get total count of registered users"""
        async with self.get_connection() as conn:
            cursor = conn.execute("SELECT COUNT(*) FROM user_registrations")
            result = cursor.fetchone()
            return result[0] if result else 0
    
    async def add_bot_promoted_admin(self, chat_id: int, user_id: int, promoted_by: int):
        """Add admin to bot-promoted admins tracking"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO bot_promoted_admins (chat_id, user_id, promoted_by) VALUES (?, ?, ?)",
                (chat_id, user_id, promoted_by)
            )
            conn.commit()
    
    async def remove_bot_promoted_admin(self, chat_id: int, user_id: int):
        """Remove admin from bot-promoted admins tracking"""
        async with self.get_connection() as conn:
            conn.execute(
                "DELETE FROM bot_promoted_admins WHERE chat_id=? AND user_id=?",
                (chat_id, user_id)
            )
            conn.commit()
    
    async def is_bot_promoted_admin(self, chat_id: int, user_id: int) -> bool:
        """Check if user is a bot-promoted admin"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT 1 FROM bot_promoted_admins WHERE chat_id=? AND user_id=? LIMIT 1",
                (chat_id, user_id)
            )
            return bool(cursor.fetchone())
    
    async def enable_full_protection(self, chat_id: int, enabled_by: int):
        """Enable full protection for a chat"""
        async with self.get_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO full_protection (chat_id, enabled, enabled_by) VALUES (?, 1, ?)",
                (chat_id, enabled_by)
            )
            conn.commit()
    
    async def disable_full_protection(self, chat_id: int):
        """Disable full protection for a chat"""
        async with self.get_connection() as conn:
            conn.execute(
                "UPDATE full_protection SET enabled=0 WHERE chat_id=?",
                (chat_id,)
            )
            conn.commit()
    
    async def is_full_protection_enabled(self, chat_id: int) -> bool:
        """Check if full protection is enabled for a chat"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT enabled FROM full_protection WHERE chat_id=? LIMIT 1",
                (chat_id,)
            )
            result = cursor.fetchone()
            return bool(result and result[0] == 1)
    
    async def create_whisper(self, chat_id: int, from_user_id: int, to_user_id: int, message: str, group_message_id: int) -> int:
        """Create a new whisper"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "INSERT INTO whispers (chat_id, from_user_id, to_user_id, message, group_message_id) VALUES (?, ?, ?, ?, ?)",
                (chat_id, from_user_id, to_user_id, message, group_message_id)
            )
            conn.commit()
            return cursor.lastrowid
    
    async def get_whisper(self, whisper_id: int):
        """Get whisper by ID"""
        async with self.get_connection() as conn:
            cursor = conn.execute(
                "SELECT id, chat_id, from_user_id, to_user_id, message, seen, group_message_id FROM whispers WHERE id=?",
                (whisper_id,)
            )
            return cursor.fetchone()
    
    async def mark_whisper_seen(self, whisper_id: int):
        """Mark whisper as seen"""
        async with self.get_connection() as conn:
            conn.execute(
                "UPDATE whispers SET seen=1 WHERE id=?",
                (whisper_id,)
            )
            conn.commit()

# Global database instance
db = DatabaseManager()

# ---------- Message Processing Classes ----------
class MessageAnalyzer:
    """Advanced message analysis and filtering"""

    def __init__(self):
        self.user_message_cache: Dict[int, str] = {}
        self.user_edit_tracking: Dict[int, Set[int]] = {}
        self.user_message_timestamps: Dict[int, list] = {}  # user_id -> [(timestamp, message_id), ...]

    def contains_phone_number(self, text: str) -> bool:
        """Detect phone numbers using multiple patterns"""
        if not text:
            return False

        # Clean text for better detection
        cleaned_text = re.sub(r'[^0-9٠-٩+\-\s\(\)\.]', ' ', text)

        for pattern in PHONE_PATTERNS:
            if pattern.search(cleaned_text):
                return True

        return False

    def contains_credit_card(self, text: str) -> bool:
        """Detect credit card numbers"""
        if not text:
            return False

        # Remove spaces and hyphens for detection
        cleaned_text = re.sub(r'[\s\-]', '', text)

        for pattern in CREDIT_CARD_PATTERNS:
            if pattern.search(cleaned_text):
                return True

        return False

    def should_send_funny_response(self, text: str) -> bool:
        """Check if should send funny response (5% chance for normal messages)"""
        if not text or len(text) < 10:
            return False

        # 5% chance for funny response
        return random.random() < 0.05

    def contains_links(self, text: str) -> bool:
        """Detect various link formats"""
        if not text:
            return False

        for pattern in LINK_PATTERNS:
            if pattern.search(text):
                return True

        return False

    def contains_banned_content(self, text: str, username: str = "", full_name: str = "") -> bool:
        """Check for banned keywords in text or user info"""
        if not text and not username and not full_name:
            return False

        content_to_check = f"{text} {username} {full_name}".lower()

        for keyword in BANNED_KEYWORDS:
            if keyword in content_to_check:
                return True

        return False

    def is_duplicate_message(self, user_id: int, text: str) -> bool:
        """Check for duplicate messages"""
        if not text:
            return False

        last_message = self.user_message_cache.get(user_id)
        is_duplicate = last_message == text
        self.user_message_cache[user_id] = text

        return is_duplicate

    def track_edit(self, user_id: int, message_id: int) -> bool:
        """Track message edits"""
        if user_id not in self.user_edit_tracking:
            self.user_edit_tracking[user_id] = set()

        if message_id in self.user_edit_tracking[user_id]:
            return True  # Already edited

        self.user_edit_tracking[user_id].add(message_id)
        return False

    def has_contact(self, message) -> bool:
        """Check if message contains a contact"""
        return bool(message.contact)
    
    def is_forwarded(self, message) -> bool:
        """Check if message is forwarded"""
        return bool(message.forward_origin or getattr(message, 'forward_from', None) or getattr(message, 'forward_from_chat', None))
    
    def is_quote_from_channel(self, message) -> bool:
        """Check if message is a quote/reply from a channel"""
        if message.reply_to_message:
            reply = message.reply_to_message
            # Check if the replied message is from a channel
            if reply.sender_chat and reply.sender_chat.type == 'channel':
                return True
        return False
    
    def is_external_quote(self, message, current_chat_id: int) -> bool:
        """Check if message is replying to an external quote (from outside the group)"""
        
        # NEW: Check for external_reply - This is THE KEY for external quotes!
        # message.external_reply indicates a reply from a different chat/forum topic
        if hasattr(message, 'external_reply') and message.external_reply:
            # This message is definitely an external quote/reply
            return True
        
        # Check for old-style reply_to_message - OLD METHOD (fallback)
        if message.reply_to_message:
            reply = message.reply_to_message
            
            # Check if it's a forwarded message (external content)
            if reply.forward_origin or getattr(reply, 'forward_from', None) or getattr(reply, 'forward_from_chat', None):
                return True
            
            # Check if the reply is from a different chat
            if hasattr(reply, 'chat') and reply.chat and reply.chat.id != current_chat_id:
                return True
            
            # Check if it's from a channel sender in the group
            if reply.sender_chat and reply.sender_chat.id != current_chat_id:
                return True
        
        return False
    
    def is_spam_flooding(self, user_id: int, message_id: int) -> tuple[bool, list]:
        """Check if user is flooding (5 or more messages in 2 seconds). Returns (is_spam, message_ids_to_delete)"""
        current_time = datetime.now(timezone.utc).timestamp()
        
        # Initialize user's message list if not exists
        if user_id not in self.user_message_timestamps:
            self.user_message_timestamps[user_id] = []
        
        # Add current message
        self.user_message_timestamps[user_id].append((current_time, message_id))
        
        # Remove messages older than 2 seconds
        self.user_message_timestamps[user_id] = [
            (ts, mid) for ts, mid in self.user_message_timestamps[user_id]
            if current_time - ts <= 2
        ]
        
        # Check if 5 or more messages in 2 seconds
        message_count = len(self.user_message_timestamps[user_id])
        
        if message_count >= 5:
            # Get message IDs to delete (all messages in the flood)
            message_ids = [mid for ts, mid in self.user_message_timestamps[user_id]]
            return True, message_ids
        
        return False, []
    
    def contains_english(self, text: str) -> bool:
        """Check if text contains English letters"""
        if not text:
            return False
        return bool(re.search(r'[a-zA-Z]', text))
    
    def contains_russian(self, text: str) -> bool:
        """Check if text contains Russian/Cyrillic letters"""
        if not text:
            return False
        return bool(re.search(r'[а-яА-ЯёЁ]', text))

class ModerationEngine:
    """Core moderation logic"""

    def __init__(self, analyzer: MessageAnalyzer, database: DatabaseManager):
        self.analyzer = analyzer
        self.db = database

    async def should_delete_message(self, message, chat_id: int) -> tuple[bool, str, bool]:
        """Determine if message should be deleted and why. Returns (should_delete, reason, should_mute)"""
        user = message.from_user
        if not user:
            return True, "No user info", False

        # Check if full protection is enabled (must be checked BEFORE trusted user check)
        full_protection_enabled = await self.db.is_full_protection_enabled(chat_id)
        
        # Full protection filters (apply to EVERYONE except developer and global owners)
        if full_protection_enabled:
            # Skip only developer and global owners from full protection
            is_exempt = user.id == DEVELOPER_ID or await self.db.is_global_owner(user.id)
            
            if not is_exempt:
                # Ban bots and channels immediately
                if user.is_bot or (message.sender_chat and message.sender_chat.type == 'channel'):
                    return True, "Bot/Channel (Full Protection)", False
                
                # Check for quotes from channels
                if self.analyzer.is_quote_from_channel(message):
                    return True, "Quote from channel (Full Protection)", False
                
                # Check for forwarded messages
                if self.analyzer.is_forwarded(message):
                    return True, "Forwarded message (Full Protection)", False
                
                # Check for contacts
                if self.analyzer.has_contact(message):
                    return True, "Contains contact (Full Protection)", True
                
                text = message.text or message.caption or ""
                
                # Check for phone numbers (strict)
                if self.analyzer.contains_phone_number(text):
                    return True, "Contains phone number (Full Protection)", False
                
                # Check for links (strict)
                if self.analyzer.contains_links(text):
                    return True, "Contains links (Full Protection)", False
                
                # Check for English language
                if self.analyzer.contains_english(text):
                    return True, "Contains English (Full Protection)", False
                
                # Check for Russian language
                if self.analyzer.contains_russian(text):
                    return True, "Contains Russian (Full Protection)", False

        # Skip trusted users, developers, and global owners for standard moderation
        if await self.db.is_trusted(chat_id, user.id) or user.id == DEVELOPER_ID or await self.db.is_global_owner(user.id):
            return False, "Trusted user", False

        # Standard moderation (without full protection)
        if not full_protection_enabled:
            # Delete bot messages
            if user.is_bot:
                return True, "Bot message", False

            # Check for forwarded messages
            if self.analyzer.is_forwarded(message):
                return True, "Forwarded message", False
            
            # Check for quotes from channels
            if self.analyzer.is_quote_from_channel(message):
                return True, "Quote from channel", False

            # Check for contacts (highest priority - requires muting)
            if self.analyzer.has_contact(message):
                return True, "Contains contact", True

        text = message.text or message.caption or ""

        # Check for phone numbers (high priority)
        if self.analyzer.contains_phone_number(text):
            return True, "Contains phone number", False

        # Check for credit cards
        if self.analyzer.contains_credit_card(text):
            return True, "Contains credit card", False

        # Check for banned content
        if self.analyzer.contains_banned_content(
            text, 
            user.username or "", 
            user.full_name or ""
        ):
            return True, "Contains banned content", False

        # Check for links (only if full protection is not enabled, as it's already checked above)
        if not full_protection_enabled and self.analyzer.contains_links(text):
            return True, "Contains links", False

        # Check for duplicates
        if self.analyzer.is_duplicate_message(user.id, text):
            return True, "Duplicate message", False

        # Check Arabic requirement (if text exists)
        if text and not ARABIC_PATTERN.search(text):
            return True, "Non-Arabic text", False

        return False, "Message approved", False

    async def process_message_deletion(self, message, context: ContextTypes.DEFAULT_TYPE, reason: str, should_mute: bool = False):
        """Delete message and log action silently"""
        try:
            await message.delete()
            
            if should_mute and message.from_user:
                await self.mute_user_for_contact(message, context)
            
            await self.db.log_action(
                message.chat_id,
                message.from_user.id if message.from_user else 0,
                message.message_id,
                "DELETE",
                reason
            )
            logger.info(f"Deleted message {message.message_id} in chat {message.chat_id}: {reason}")
        except Exception as e:
            logger.error(f"Failed to delete message: {e}")

    async def mute_user_for_contact(self, message, context: ContextTypes.DEFAULT_TYPE):
        """Mute user for 50 minutes for sending contact"""
        try:
            user = message.from_user
            chat_id = message.chat_id
            
            # Restrict user permissions
            restricted_permissions = ChatPermissions(
                can_send_messages=False,
                can_send_media_messages=False,
                can_send_polls=False,
                can_send_other_messages=False,
                can_add_web_page_previews=False,
                can_change_info=False,
                can_invite_users=False,
                can_pin_messages=False
            )
            
            from datetime import datetime, timedelta, timezone
            until_date = datetime.now(timezone.utc) + timedelta(minutes=50)
            
            await context.bot.restrict_chat_member(
                chat_id=chat_id,
                user_id=user.id,
                permissions=restricted_permissions,
                until_date=until_date
            )
            
            # Store mute info in database  
            await self.db.mute_user(chat_id, user.id, 0, 50, "Sent contact", message.message_id or 0)
            
            # Send unmute button (without username)
            keyboard = [[InlineKeyboardButton("🔓 إلغاء الكتم", callback_data=f"unmute_{chat_id}_{user.id}")]]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await context.bot.send_message(
                chat_id=chat_id,
                text="⚠️ تم كتم مستخدم لإرسال جهة اتصال (50 دقيقة)",
                reply_markup=reply_markup
            )
            
            logger.info(f"Muted user {user.id} for sending contact in chat {chat_id}")
            
        except Exception as e:
            logger.error(f"Failed to mute user: {e}")

    async def schedule_media_deletion(self, context: ContextTypes.DEFAULT_TYPE, chat_id: int, message_id: int, media_type: str):
        """Schedule media deletion after 2 minutes"""
        await asyncio.sleep(config.media_delete_minutes * 60)  # 2 minutes
        try:
            await context.bot.delete_message(chat_id, message_id)
            await self.db.log_action(chat_id, 0, message_id, "DELETE_MEDIA", f"Scheduled deletion: {media_type}")
            logger.info(f"Scheduled deletion: {media_type} message {message_id} in chat {chat_id}")
        except Exception as e:
            logger.error(f"Failed to delete scheduled media: {e}")

# Global instances
analyzer = MessageAnalyzer()
moderation_engine = ModerationEngine(analyzer, db)

# Temporary storage for admin promotion sessions
# Format: {chat_id: {user_id: {'target_user_id': int, 'permissions': {...}}}}
promotion_sessions: Dict[int, Dict[int, Dict[str, Any]]] = {}

# ---------- Developer Photo Handler ----------
async def get_developer_photo(context: ContextTypes.DEFAULT_TYPE) -> Optional[str]:
    """Get developer's profile photo file_id"""
    try:
        # Get developer's profile photos
        photos = await context.bot.get_user_profile_photos(DEVELOPER_ID, limit=1)
        
        if not photos.photos or len(photos.photos) == 0:
            return None
        
        # Get the largest photo
        photo = photos.photos[0][-1]
        
        return photo.file_id
    except Exception as e:
        logger.error(f"Failed to get developer photo: {e}")
        return None

# ---------- Message Handlers ----------
async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages with advanced filtering"""
    if not update.message:
        return

    message = update.message
    chat_id = message.chat_id
    user = message.from_user

    try:
        # Handle private messages
        if message.chat.type == 'private':
            await handle_private_message(update, context)
            return
        
        # Auto-ban users who add bots (except developer and global owners)
        if message.new_chat_members and user:
            # Get all bot members
            bot_members = [member for member in message.new_chat_members if member.is_bot]
            
            if bot_members:
                # Check if user is developer or global owner (exempt from ban)
                is_exempt = user.id == DEVELOPER_ID or await db.is_global_owner(user.id)
                
                if not is_exempt:
                    try:
                        # Ban all added bots first
                        for bot in bot_members:
                            try:
                                await context.bot.ban_chat_member(chat_id=chat_id, user_id=bot.id)
                                logger.info(f"Banned bot {bot.id} in chat {chat_id}")
                            except Exception as e:
                                logger.error(f"Failed to ban bot {bot.id}: {e}")
                        
                        # Ban the user who added the bots
                        await context.bot.ban_chat_member(chat_id=chat_id, user_id=user.id)
                        
                        # Delete the service message
                        try:
                            await message.delete()
                        except:
                            pass
                        
                        # Send notification with unban button
                        keyboard = [[InlineKeyboardButton("🔓 إلغاء الحظر", callback_data=f"unban_{chat_id}_{user.id}")]]
                        reply_markup = InlineKeyboardMarkup(keyboard)
                        
                        await context.bot.send_message(
                            chat_id=chat_id,
                            text=f"🚫 تم حظر [{user.full_name or user.username or user.id}](tg://user?id={user.id})\n\nالسبب: إضافة بوتات ممنوعة",
                            reply_markup=reply_markup,
                            parse_mode='Markdown'
                        )
                        
                        logger.info(f"Banned user {user.id} for adding bots in chat {chat_id}")
                        return
                    except Exception as e:
                        logger.error(f"Failed to ban user for adding bot: {e}")
        
        # Check for restrict/ban commands by reply (for global owners and developer)
        if message.reply_to_message and message.text and user:
            if await db.is_global_owner(user.id) or user.id == DEVELOPER_ID:
                target_user = message.reply_to_message.from_user
                if target_user:
                    text_lower = message.text.strip().lower()
                    
                    # Restrict command
                    if text_lower == "تقييد":
                        try:
                            # Check if target is admin, demote first
                            try:
                                target_member = await context.bot.get_chat_member(chat_id, target_user.id)
                                if target_member.status in ['administrator', 'creator']:
                                    # Demote admin first
                                    await context.bot.promote_chat_member(
                                        chat_id=chat_id,
                                        user_id=target_user.id,
                                        can_delete_messages=False,
                                        can_restrict_members=False,
                                        can_promote_members=False,
                                        can_change_info=False,
                                        can_invite_users=False,
                                        can_pin_messages=False,
                                        can_manage_chat=False,
                                        can_manage_video_chats=False,
                                        can_manage_topics=False,
                                        can_post_messages=False,
                                        can_edit_messages=False,
                                        can_post_stories=False,
                                        can_edit_stories=False,
                                        can_delete_stories=False,
                                        is_anonymous=False
                                    )
                                    logger.info(f"Demoted admin {target_user.id} before restriction")
                            except Exception as e:
                                logger.error(f"Error checking/demoting admin: {e}")
                            
                            # Restrict the user
                            restricted_permissions = ChatPermissions(
                                can_send_messages=False,
                                can_send_media_messages=False,
                                can_send_polls=False,
                                can_send_other_messages=False,
                                can_add_web_page_previews=False
                            )
                            
                            await context.bot.restrict_chat_member(
                                chat_id=chat_id,
                                user_id=target_user.id,
                                permissions=restricted_permissions
                            )
                            
                            await message.reply_text(
                                f"✅ تم تقييد [{target_user.full_name or target_user.username or target_user.id}](tg://user?id={target_user.id})",
                                parse_mode='Markdown'
                            )
                            logger.info(f"User {target_user.id} restricted by {user.id} via reply command")
                            return
                            
                        except Exception as e:
                            logger.error(f"Failed to restrict user: {e}")
                            await message.reply_text("❌ فشل تقييد المستخدم")
                            return
                    
                    # Ban command
                    elif text_lower == "حظر":
                        try:
                            # Check if target is admin, demote first
                            try:
                                target_member = await context.bot.get_chat_member(chat_id, target_user.id)
                                if target_member.status in ['administrator', 'creator']:
                                    # Demote admin first
                                    await context.bot.promote_chat_member(
                                        chat_id=chat_id,
                                        user_id=target_user.id,
                                        can_delete_messages=False,
                                        can_restrict_members=False,
                                        can_promote_members=False,
                                        can_change_info=False,
                                        can_invite_users=False,
                                        can_pin_messages=False,
                                        can_manage_chat=False,
                                        can_manage_video_chats=False,
                                        can_manage_topics=False,
                                        can_post_messages=False,
                                        can_edit_messages=False,
                                        can_post_stories=False,
                                        can_edit_stories=False,
                                        can_delete_stories=False,
                                        is_anonymous=False
                                    )
                                    logger.info(f"Demoted admin {target_user.id} before ban")
                            except Exception as e:
                                logger.error(f"Error checking/demoting admin: {e}")
                            
                            # Ban the user
                            await context.bot.ban_chat_member(
                                chat_id=chat_id,
                                user_id=target_user.id
                            )
                            
                            # Send message with unban button
                            keyboard = [[InlineKeyboardButton("🔓 إلغاء الحظر", callback_data=f"unban_{chat_id}_{target_user.id}")]]
                            reply_markup = InlineKeyboardMarkup(keyboard)
                            
                            await message.reply_text(
                                f"✅ تم حظر [{target_user.full_name or target_user.username or target_user.id}](tg://user?id={target_user.id})",
                                reply_markup=reply_markup,
                                parse_mode='Markdown'
                            )
                            logger.info(f"User {target_user.id} banned by {user.id} via reply command")
                            return
                            
                        except Exception as e:
                            logger.error(f"Failed to ban user: {e}")
                            await message.reply_text("❌ فشل حظر المستخدم")
                            return
        
        # Skip spam check for trusted users
        if user and not (await db.is_trusted(chat_id, user.id) or user.id == DEVELOPER_ID or await db.is_global_owner(user.id)):
            # Check for spam flooding
            is_spam, message_ids_to_delete = analyzer.is_spam_flooding(user.id, message.message_id)
            
            if is_spam:
                # Restrict user
                try:
                    restricted_permissions = ChatPermissions(
                        can_send_messages=False,
                        can_send_media_messages=False,
                        can_send_polls=False,
                        can_send_other_messages=False,
                        can_add_web_page_previews=False
                    )
                    
                    from datetime import timedelta
                    until_date = datetime.now(timezone.utc) + timedelta(minutes=10)
                    
                    await context.bot.restrict_chat_member(
                        chat_id=chat_id,
                        user_id=user.id,
                        permissions=restricted_permissions,
                        until_date=until_date
                    )
                    
                    # Delete all flood messages
                    for msg_id in message_ids_to_delete:
                        try:
                            await context.bot.delete_message(chat_id=chat_id, message_id=msg_id)
                        except Exception as e:
                            logger.error(f"Failed to delete flood message {msg_id}: {e}")
                    
                    # Send unmute button
                    keyboard = [[InlineKeyboardButton("🔓 إلغاء الكتم", callback_data=f"unmute_{chat_id}_{user.id}")]]
                    reply_markup = InlineKeyboardMarkup(keyboard)
                    
                    await context.bot.send_message(
                        chat_id=chat_id,
                        text=f"⚠️ تم تقييد [{user.full_name or user.username or user.id}](tg://user?id={user.id}) لإرسال رسائل متكررة (10 دقائق)",
                        reply_markup=reply_markup,
                        parse_mode='Markdown'
                    )
                    
                    # Clear user's message timestamps
                    analyzer.user_message_timestamps[user.id] = []
                    
                    logger.info(f"User {user.id} restricted for spam flooding in chat {chat_id}")
                    return
                    
                except Exception as e:
                    logger.error(f"Failed to restrict spam user: {e}")
        
        # Auto-ban channels when full protection is enabled
        if message.sender_chat and message.sender_chat.type == 'channel':
            full_protection_enabled = await db.is_full_protection_enabled(chat_id)
            
            if full_protection_enabled:
                try:
                    # Ban the channel sender
                    await context.bot.ban_chat_sender_chat(
                        chat_id=chat_id,
                        sender_chat_id=message.sender_chat.id
                    )
                    
                    # Delete the channel message
                    await message.delete()
                    
                    logger.info(f"Banned channel {message.sender_chat.id} in chat {chat_id} (full protection)")
                    return
                except Exception as e:
                    logger.error(f"Failed to ban channel: {e}")
        
        # Check for external quote replies - Delete with warning system
        if user and analyzer.is_external_quote(message, chat_id):
            # Check if user is developer or global owner (exempt)
            is_exempt = user.id == DEVELOPER_ID or await db.is_global_owner(user.id)
            
            if not is_exempt:
                try:
                    # Delete the message silently
                    await message.delete()
                    
                    # Add hidden warning
                    warning_count = await db.add_warning(chat_id, user.id)
                    
                    logger.info(f"Deleted quote from user {user.id} in chat {chat_id} - Warning {warning_count}/3")
                    
                    # If user has 3 warnings, restrict them
                    if warning_count >= 3:
                        try:
                            # Restrict the user
                            restricted_permissions = ChatPermissions(
                                can_send_messages=False,
                                can_send_media_messages=False,
                                can_send_polls=False,
                                can_send_other_messages=False,
                                can_add_web_page_previews=False
                            )
                            
                            await context.bot.restrict_chat_member(
                                chat_id=chat_id,
                                user_id=user.id,
                                permissions=restricted_permissions
                            )
                            
                            # Reset warnings after restriction
                            await db.reset_warnings(chat_id, user.id)
                            
                            logger.info(f"Restricted user {user.id} after 3 quote warnings in chat {chat_id}")
                        except Exception as e:
                            logger.error(f"Failed to restrict user after warnings: {e}")
                    
                    return
                except Exception as e:
                    logger.error(f"Failed to delete external quote: {e}")
        
        # Check for "المطور" command in groups
        if message.text and message.text.strip() == "المطور":
            try:
                # Get developer info
                developer = await context.bot.get_chat(DEVELOPER_ID)
                
                # Get developer name (escaped for MarkdownV2)
                developer_name = developer.full_name or developer.first_name or "المطور"
                escaped_name = escape_markdown(developer_name, version=2)
                
                # Get developer bio (escaped for MarkdownV2)
                developer_bio = developer.bio if developer.bio else "لا يوجد بايو"
                escaped_bio = escape_markdown(developer_bio, version=2)
                
                # Build developer info text with MarkdownV2
                dev_info_text = (
                    f"‏Developer Bot ↦\n"
                    f"━━━━━━━━\n"
                    f"‏USE ↦ [{escaped_name}](https://t\\.me/i\\_a\\_5)\n"
                    f"‏Bio ↦ {escaped_bio}\n"
                    f"━━━━━━━━"
                )
                
                # Get developer photo
                photo = await get_developer_photo(context)
                
                if photo:
                    # Send photo with caption
                    await message.reply_photo(
                        photo=photo,
                        caption=dev_info_text,
                        parse_mode='MarkdownV2'
                    )
                else:
                    # Fallback to text if photo unavailable
                    await message.reply_text(
                        dev_info_text,
                        parse_mode='MarkdownV2'
                    )
                
                logger.info(f"Developer info shown in chat {chat_id}")
                return
                
            except Exception as e:
                logger.error(f"Failed to show developer info: {e}")
                # Fallback to plain text if Markdown fails
                try:
                    plain_text = (
                        f"‏Developer Bot ↦\n"
                        f"━━━━━━━━\n"
                        f"‏USE ↦ {developer_name}\n"
                        f"‏https://t.me/i_a_5\n"
                        f"‏Bio ↦ {developer_bio}\n"
                        f"━━━━━━━━"
                    )
                    await message.reply_text(plain_text)
                except:
                    pass
        
        # Auto-restrict users who send contacts
        if message.contact and user:
            # Check if user is developer or global owner (exempt from restriction)
            is_exempt = user.id == DEVELOPER_ID or await db.is_global_owner(user.id)
            
            if not is_exempt:
                try:
                    # Restrict the user
                    restricted_permissions = ChatPermissions(
                        can_send_messages=False,
                        can_send_polls=False,
                        can_send_other_messages=False,
                        can_add_web_page_previews=False
                    )
                    
                    await context.bot.restrict_chat_member(
                        chat_id=chat_id,
                        user_id=user.id,
                        permissions=restricted_permissions
                    )
                    
                    # Delete the contact message
                    try:
                        await message.delete()
                    except:
                        pass
                    
                    # Send notification with unmute button (developer only)
                    keyboard = [[InlineKeyboardButton("🔓 إلغاء تقييد", callback_data=f"dev_unmute_{chat_id}_{user.id}")]]
                    reply_markup = InlineKeyboardMarkup(keyboard)
                    
                    await context.bot.send_message(
                        chat_id=chat_id,
                        text=f"⚠️ تم كتم [{user.full_name or user.username or user.id}](tg://user?id={user.id}) لأنه قام بالتخريب",
                        reply_markup=reply_markup,
                        parse_mode='Markdown'
                    )
                    
                    logger.info(f"Restricted user {user.id} for sending contact in chat {chat_id}")
                    return
                except Exception as e:
                    logger.error(f"Failed to restrict user for contact: {e}")
        
        # Check if message should be deleted
        should_delete, reason, should_mute = await moderation_engine.should_delete_message(message, chat_id)

        if should_delete:
            await moderation_engine.process_message_deletion(message, context, reason, should_mute)

    except Exception as e:
        logger.error(f"Error handling message {message.message_id}: {e}")

async def handle_private_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle private messages - whispers only"""
    message = update.message
    user = message.from_user
    
    if not user:
        return
    
    try:
        # ONLY handle whisper mode - let /start handle welcome messages
        if 'whisper_mode' in context.user_data:
            whisper_data = context.user_data['whisper_mode']
            chat_id = whisper_data['chat_id']
            from_user_id = whisper_data['from_user_id']  # Sender
            to_user_id = whisper_data['to_user_id']  # Recipient
            
            # Make sure current user is the sender
            if user.id != from_user_id:
                await message.reply_text(" غير صالح")
                return
            
            # Get message text (support text only for now)
            if not message.text:
                await message.reply_text("• يمكنك إرسال نصوص فقط في الهمسات")
                return
            
            # Save whisper to database
            # Escape user name for Markdown
            sender_name = escape_markdown(user.full_name or user.username or str(user.id), version=2)
            
            # Get recipient info for display name
            try:
                to_user = await context.bot.get_chat(to_user_id)
                to_name = escape_markdown(to_user.full_name or to_user.username or str(to_user_id), version=2)
            except:
                to_name = escape_markdown(str(to_user_id), version=2)
            
            group_message = await context.bot.send_message(
                chat_id=chat_id,
                text=f"• ياحلو ↤ [{to_name}](tg://user?id={to_user_id})\n\n• وصلتك همسة سرية من ↤ ︎[{sender_name}](tg://user?id={user.id})\n\n• انت وحدك تقدر تشوفها",
                parse_mode='MarkdownV2'
            )
            
            # Save whisper: from_user_id = sender, to_user_id = recipient
            whisper_id = await db.create_whisper(
                chat_id=chat_id,
                from_user_id=from_user_id,  # Sender from whisper_mode
                to_user_id=to_user_id,  # Recipient from whisper_mode
                message=message.text,
                group_message_id=group_message.message_id
            )
            
            # Delete the whisper from private chat
            await message.delete()
            
            # Create deep link for reply (only to_user_id can reply to from_user_id)
            # Format: hms{chat_id}from_{sender}_allow_{intended_replier}
            reply_deep_link = f"https://t.me/{context.bot.username}?start=hms{chat_id}from_{from_user_id}_allow_{to_user_id}"
            
            # Send buttons in group for recipient to view and reply to whisper
            keyboard = [
                [InlineKeyboardButton("رؤية الهمسة", callback_data=f"view_whisper_{whisper_id}")],
                [InlineKeyboardButton("رد على الهمسة", url=reply_deep_link)]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await context.bot.edit_message_text(
                chat_id=chat_id,
                message_id=group_message.message_id,
                text=f"• ياحلو ↤ [{to_name}](tg://user?id={to_user_id})\n\n• وصلتك همسة سرية من ↤ ︎[{sender_name}](tg://user?id={user.id})\n\n• انت وحدك تقدر تشوفها",
                reply_markup=reply_markup,
                parse_mode='MarkdownV2'
            )
            
            # Confirm to sender
            await context.bot.send_message(
                chat_id=user.id,
                text="• تم ارسال الهمسة"
            )
            
            # Clear whisper mode
            del context.user_data['whisper_mode']
            
            logger.info(f"Whisper {whisper_id} created from {from_user_id} to {to_user_id} in chat {chat_id}")
            return
        
    except Exception as e:
        logger.error(f"Error handling private message: {e}")

async def handle_statistics_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle statistics command - show total users count"""
    if not update.message:
        return
    
    message = update.message
    user = message.from_user
    
    # Only developer can view statistics
    if not user or user.id != DEVELOPER_ID:
        return
    
    try:
        # Get total users count
        users_count = await db.get_users_count()
        
        await message.reply_text(
            f"📊 **إحصائيات البوت**\n\n"
            f"👥 عدد المستخدمين: {users_count}",
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logger.error(f"Error handling statistics command: {e}")

async def handle_admin_panel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle admin panel command (developer only)"""
    if not update.message:
        return
    
    message = update.message
    user = message.from_user
    
    # Check if user is developer
    if not user or user.id != DEVELOPER_ID:
        return  # Silent mode
    
    try:
        # Create admin panel buttons
        keyboard = [
            [InlineKeyboardButton("👑 المالكين الأساسيين", callback_data="admin_global_owners")],
            [InlineKeyboardButton("👮‍♂️ الأدمنية", callback_data="admin_local_admins")],
            [InlineKeyboardButton("🛡️ إعدادات الحماية", callback_data="admin_protection_settings")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await message.reply_text(
            "🔧 **لوحة تحكم المشرفين**\n\n"
            "اختر القسم الذي تريد إدارته:",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logger.error(f"Error handling admin panel: {e}")

async def handle_edited_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle edited messages - delete all edits immediately"""
    if not update.edited_message:
        return

    edited_message = update.edited_message
    user = edited_message.from_user
    chat_id = edited_message.chat_id

    if not user:
        return

    try:
        # Skip trusted users, developers, and global owners
        if await db.is_trusted(chat_id, user.id) or user.id == DEVELOPER_ID or await db.is_global_owner(user.id):
            return
        
        # If full protection is enabled, delete ALL edits immediately
        if await db.is_full_protection_enabled(chat_id):
            await edited_message.delete()
            logger.info(f"Deleted edited message {edited_message.message_id} in chat {chat_id} (Full Protection)")
            return

        # Check if edited message contains link or contact
        text = edited_message.text or edited_message.caption or ""
        contains_link = analyzer.contains_links(text)
        contains_contact = analyzer.has_contact(edited_message)
        
        # If edited to link or contact, notify admins and owners
        if contains_link or contains_contact:
            violation_type = "رابط" if contains_link else "جهة اتصال"
            
            # Get all admins and global owners
            admins = await db.get_admins_list(chat_id)
            global_owners_data = await db.get_global_owners_list()
            
            # Prepare notification message
            notification = f"⚠️ **تنبيه أمني**\n\n"
            notification += f"قام المستخدم [{user.full_name or user.username or user.id}](tg://user?id={user.id}) بتعديل رسالة إلى {violation_type}\n\n"
            notification += f"📝 المحتوى المعدل:\n{text[:100]}...\n\n" if len(text) > 100 else f"📝 المحتوى المعدل:\n{text}\n\n"
            
            # Add admin names
            if admins:
                notification += "👥 **الأدمنية المحليين:**\n"
                for admin in admins:
                    admin_id = admin[0]
                    notification += f"• [{admin_id}](tg://user?id={admin_id})\n"
            
            # Add global owner names
            if global_owners_data:
                notification += "\n👑 **المالكين الأساسيين:**\n"
                for owner in global_owners_data:
                    owner_id = owner[0]
                    notification += f"• [{owner_id}](tg://user?id={owner_id})\n"
            
            # Send notification to the group
            try:
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=notification,
                    parse_mode='Markdown'
                )
            except Exception as e:
                logger.error(f"Failed to send edit notification: {e}")

        # Delete ALL edited messages (no time window)
        await moderation_engine.process_message_deletion(
            edited_message, 
            context, 
            "Message edited"
        )

    except Exception as e:
        logger.error(f"Error handling edited message {edited_message.message_id}: {e}")

# ---------- Whisper System ----------
async def handle_whisper_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle whisper request when user replies with 'همسة'"""
    if not update.message or not update.message.reply_to_message:
        return
    
    message = update.message
    replied_message = message.reply_to_message
    from_user = message.from_user
    to_user = replied_message.from_user if replied_message else None
    chat_id = message.chat_id
    
    if not from_user or not to_user:
        return
    
    # Can't whisper to yourself
    if from_user.id == to_user.id:
        await message.reply_text("غبي تهمس لنفسك؟؟")
        return
    
    # Can't whisper to bots
    if to_user.is_bot:
        await message.reply_text("غب انت تهمس للبوت ؟؟؟؟")
        return
    
    try:
        # Delete the whisper request message
        await message.delete()
        
        # Create deep link with format: hms{chat_id}from_id{to_user_id}
        # to_user.id is the recipient who will receive the whisper
        deep_link = f"https://t.me/{context.bot.username}?start=hms{chat_id}from_id{to_user.id}"
        
        # Send message with button to start whisper
        keyboard = [[InlineKeyboardButton("اهمس هنا", url=deep_link)]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        # Escape Markdown for user names
        from_name = escape_markdown(from_user.full_name or from_user.username or str(from_user.id), version=2)
        to_name = escape_markdown(to_user.full_name or to_user.username or str(to_user.id), version=2)
        
        await context.bot.send_message(
            chat_id=chat_id,
            text=f"• تم تحديد الهمسه لـ ↤ [{to_name}](tg://user?id={to_user.id}) \n•اضغط الزر لكتابة الهمسة",
            reply_markup=reply_markup,
            parse_mode='MarkdownV2'
        )
        
        logger.info(f"Whisper request from {from_user.id} to {to_user.id} in chat {chat_id}")
        
    except Exception as e:
        logger.error(f"Error handling whisper request: {e}")

# ---------- Button Handlers ----------
async def handle_callback_query(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle callback queries from inline buttons"""
    query = update.callback_query
    
    if not query:
        return
    
    try:
        # Get basic data
        data = query.data if query.data else ""
        user = query.from_user
        
        # Get chat_id safely
        chat_id = None
        if query.message and query.message.chat:
            chat_id = query.message.chat.id
        
        if not chat_id or not user or not data:
            await query.answer("❌ خطأ في البيانات", show_alert=True)
            return
        
        # Log the callback for debugging
        logger.info(f"Callback query from user {user.id} in chat {chat_id}: {data}")
        
        if data.startswith("unmute_"):
            parts = data.split("_")
            if len(parts) == 3:
                _, chat_id, user_id = parts
                chat_id, user_id = int(chat_id), int(user_id)
                
                # Check if user is global owner or developer
                if await db.is_global_owner(user.id) or user.id == DEVELOPER_ID:
                    try:
                        # Remove restrictions
                        unrestricted_permissions = ChatPermissions(
                            can_send_messages=True,
                            can_send_media_messages=True,
                            can_send_polls=True,
                            can_send_other_messages=True,
                            can_add_web_page_previews=True
                        )
                        
                        await context.bot.restrict_chat_member(
                            chat_id=chat_id,
                            user_id=user_id,
                            permissions=unrestricted_permissions
                        )
                        
                        # Remove from database
                        await db.unmute_user(chat_id, user_id)
                        
                        # Answer callback first
                        await query.answer("✅ تم إلغاء الكتم", show_alert=False)
                        
                        # Edit message to show success
                        await query.edit_message_text(
                            text="✅ تم إلغاء الكتم بنجاح"
                        )
                        
                        logger.info(f"User {user_id} unmuted by {user.id} in chat {chat_id}")
                        
                    except Exception as e:
                        await query.answer("❌ فشل إلغاء الكتم", show_alert=True)
                        logger.error(f"Failed to unmute user: {e}")
                else:
                    await query.answer("• الامر لا يخصك", show_alert=True)
        
        elif data.startswith("dev_unmute_"):
            parts = data.split("_")
            if len(parts) == 4:
                _, _, chat_id_str, user_id_str = parts
                unmute_chat_id, unmute_user_id = int(chat_id_str), int(user_id_str)
                
                # Check if user is developer only
                if user.id == DEVELOPER_ID:
                    try:
                        # Remove restrictions
                        unrestricted_permissions = ChatPermissions(
                            can_send_messages=True,
                            can_send_polls=True,
                            can_send_other_messages=True,
                            can_add_web_page_previews=True
                        )
                        
                        await context.bot.restrict_chat_member(
                            chat_id=unmute_chat_id,
                            user_id=unmute_user_id,
                            permissions=unrestricted_permissions
                        )
                        
                        # Answer callback first
                        await query.answer("✅ تم إلغاء التقييد", show_alert=False)
                        
                        # Edit message to show success
                        await query.edit_message_text(
                            text="✅ تم إلغاء التقييد بنجاح"
                        )
                        
                        logger.info(f"User {unmute_user_id} unrestricted by developer in chat {unmute_chat_id}")
                        
                    except Exception as e:
                        await query.answer("❌ فشل إلغاء التقييد", show_alert=True)
                        logger.error(f"Failed to unrestrict user: {e}")
                else:
                    await query.answer(" • هذا الزر للمطور فقط", show_alert=True)
        
        elif data.startswith("unban_"):
            parts = data.split("_")
            if len(parts) == 3:
                _, chat_id_str, user_id_str = parts
                unban_chat_id, unban_user_id = int(chat_id_str), int(user_id_str)
                
                # Check if user is global owner or developer
                if await db.is_global_owner(user.id) or user.id == DEVELOPER_ID:
                    try:
                        # Unban the user
                        await context.bot.unban_chat_member(
                            chat_id=unban_chat_id,
                            user_id=unban_user_id,
                            only_if_banned=True
                        )
                        
                        # Answer callback first
                        await query.answer("✅ تم إلغاء الحظر", show_alert=False)
                        
                        # Edit message to show success
                        await query.edit_message_text(
                            text="✅ تم إلغاء الحظر بنجاح"
                        )
                        
                        logger.info(f"User {unban_user_id} unbanned by {user.id} in chat {unban_chat_id}")
                        
                    except Exception as e:
                        await query.answer("البوت لا يملك الصلاحيات ", show_alert=True)
                        logger.error(f"Failed to unban user: {e}")
                else:
                    await query.answer("• الامر لا يخصك", show_alert=True)
        
        elif data.startswith("perm_toggle_"):
            logger.info(f"Permission toggle button pressed: {data}")
            
            # Toggle permission
            parts = data.split("_")
            if len(parts) >= 4:
                perm_key = "_".join(parts[2:-1])  # Handle multi-word permission keys
                promoter_id = int(parts[-1])
                
                logger.info(f"Extracted perm_key={perm_key}, promoter_id={promoter_id}, chat_id={chat_id}")
                
                # Check if promoter has an active session
                if chat_id in promotion_sessions and promoter_id in promotion_sessions[chat_id]:
                    session = promotion_sessions[chat_id][promoter_id]
                    chat_type = session.get('chat_type', 'supergroup')
                    logger.info(f"Session found for promoter {promoter_id}, chat_type={chat_type}")
                    
                    # Define permission labels based on chat type
                    if chat_type == 'channel':
                        perm_labels = {
                            'can_change_info': 'تغيير المعلومات',
                            'can_post_messages': 'نشر الرسائل',
                            'can_edit_messages': 'تعديل الرسائل',
                            'can_delete_messages': 'مسح الرسائل',
                            'can_invite_users': 'اضافة الاعضاء',
                            'can_manage_chat': 'إدارة القناة',
                            'can_post_stories': 'نشر القصص',
                            'can_edit_stories': 'تعديل القصص',
                            'can_delete_stories': 'مسح القصص',
                            'is_anonymous': 'مجهول الهوية'
                        }
                    else:
                        perm_labels = {
                            'can_change_info': 'تغيير المعلومات',
                            'can_delete_messages': 'مسح الرسائل',
                            'can_invite_users': 'اضافة الاعضاء',
                            'can_restrict_members': 'حظر المستخدمين',
                            'can_pin_messages': 'تثبيت الرسائل',
                            'can_promote_members': 'اضافة المشرفين',
                            'can_manage_chat': 'إدارة المجموعة',
                            'can_manage_video_chats': 'إدارة المكالمات',
                            'is_anonymous': 'مجهول الهوية'
                        }
                    
                    # Toggle the permission
                    if perm_key in session['permissions']:
                        old_value = session['permissions'][perm_key]
                        session['permissions'][perm_key] = not old_value
                        new_value = session['permissions'][perm_key]
                        
                        logger.info(f"Permission {perm_key} toggled from {old_value} to {new_value}")
                        
                        # Answer callback query to show feedback
                        status_text = "تم تفعيل" if new_value else "تم تعطيل"
                        await query.answer(f"✅ {status_text} {perm_labels.get(perm_key, perm_key)}", show_alert=False)
                    else:
                        logger.warning(f"Permission key {perm_key} not found in session permissions")
                        await query.answer("❌ خطأ في الصلاحية", show_alert=True)
                        return
                    
                    # Update the UI
                    perms = session['permissions']
                    keyboard = []
                    
                    for pk, pl in perm_labels.items():
                        if pk in perms:  # Only show permissions that exist for this chat type
                            status = "✅" if perms[pk] else "⚠️"
                            keyboard.append([
                                InlineKeyboardButton(
                                    f"{pl} ↤ {status}",
                                    callback_data=f"perm_toggle_{pk}_{promoter_id}"
                                )
                            ])
                    
                    keyboard.append([
                        InlineKeyboardButton(
                            "رفعه مشرفاً ✅",
                            callback_data=f"confirm_promote_{promoter_id}"
                        )
                    ])
                    
                    reply_markup = InlineKeyboardMarkup(keyboard)
                    
                    try:
                        chat_type_ar = "القناة" if chat_type == 'channel' else "المجموعة"
                        await query.edit_message_text(
                            f"⚙️ تعديل الصلاحيات ({chat_type_ar})\n\n"
                            f"👤 المستخدم: {session['target_name']}\n\n"
                            f"اضغط على الصلاحيات لتفعيلها/تعطيلها:",
                            reply_markup=reply_markup
                        )
                        logger.info("UI updated successfully")
                    except Exception as e:
                        logger.error(f"Failed to update UI: {e}")
                else:
                    logger.warning(f"No session found for chat_id={chat_id}, promoter_id={promoter_id}")
                    logger.info(f"Available sessions: {list(promotion_sessions.keys())}")
                    await query.answer("❌ انتهت الجلسة، يرجى المحاولة مرة أخرى", show_alert=True)
            else:
                logger.error(f"Invalid callback data format: {data}")
                await query.answer("❌ خطأ في البيانات", show_alert=True)
        
        elif data.startswith("promote_full_"):
            promoter_id = int(data.split("_")[-1])
            
            if chat_id in promotion_sessions and promoter_id in promotion_sessions[chat_id]:
                session = promotion_sessions[chat_id][promoter_id]
                target_user_id = session['target_user_id']
                chat_type = session.get('chat_type', 'supergroup')
                
                try:
                    # Get bot's own permissions to grant only what's available
                    from telegram import ChatMemberAdministrator, ChatMemberOwner
                    bot_member = await context.bot.get_chat_member(chat_id, context.bot.id)
                    
                    # Build promotion parameters with bot's available permissions
                    promote_params = {
                        'chat_id': chat_id,
                        'user_id': target_user_id
                    }
                    
                    # Check if bot is admin or owner
                    if isinstance(bot_member, ChatMemberOwner):
                        # Owner has all permissions
                        if chat_type == 'channel':
                            promote_params.update({
                                'can_change_info': True,
                                'can_post_messages': True,
                                'can_edit_messages': True,
                                'can_delete_messages': True,
                                'can_invite_users': True,
                                'can_manage_chat': True,
                                'can_post_stories': True,
                                'can_edit_stories': True,
                                'can_delete_stories': True
                            })
                        else:
                            promote_params.update({
                                'can_change_info': True,
                                'can_delete_messages': True,
                                'can_invite_users': True,
                                'can_restrict_members': True,
                                'can_pin_messages': True,
                                'can_promote_members': True,
                                'can_manage_chat': True,
                                'can_manage_video_chats': True
                            })
                    elif isinstance(bot_member, ChatMemberAdministrator):
                        # Administrator - use actual permissions
                        if chat_type == 'channel':
                            promote_params['can_change_info'] = getattr(bot_member, 'can_change_info', False)
                            promote_params['can_post_messages'] = getattr(bot_member, 'can_post_messages', False)
                            promote_params['can_edit_messages'] = getattr(bot_member, 'can_edit_messages', False)
                            promote_params['can_delete_messages'] = getattr(bot_member, 'can_delete_messages', False)
                            promote_params['can_invite_users'] = getattr(bot_member, 'can_invite_users', False)
                            promote_params['can_manage_chat'] = getattr(bot_member, 'can_manage_chat', False)
                            promote_params['can_post_stories'] = getattr(bot_member, 'can_post_stories', False)
                            promote_params['can_edit_stories'] = getattr(bot_member, 'can_edit_stories', False)
                            promote_params['can_delete_stories'] = getattr(bot_member, 'can_delete_stories', False)
                        else:
                            promote_params['can_change_info'] = getattr(bot_member, 'can_change_info', False)
                            promote_params['can_delete_messages'] = getattr(bot_member, 'can_delete_messages', False)
                            promote_params['can_invite_users'] = getattr(bot_member, 'can_invite_users', False)
                            promote_params['can_restrict_members'] = getattr(bot_member, 'can_restrict_members', False)
                            promote_params['can_pin_messages'] = getattr(bot_member, 'can_pin_messages', False)
                            promote_params['can_promote_members'] = getattr(bot_member, 'can_promote_members', False)
                            promote_params['can_manage_chat'] = getattr(bot_member, 'can_manage_chat', False)
                            promote_params['can_manage_video_chats'] = getattr(bot_member, 'can_manage_video_chats', False)
                        
                        # Check if any permissions are granted
                        has_any_perm = any(v for k, v in promote_params.items() if k not in ['chat_id', 'user_id'])
                        if not has_any_perm:
                            await query.answer("⚠️ البوت لا يملك أي صلاحيات لمنحها", show_alert=True)
                            logger.warning(f"Bot has no permissions to grant in chat {chat_id}")
                            return
                    else:
                        await query.answer("• البوت ليس مشرفاً", show_alert=True)
                        logger.error(f"Bot is not admin in chat {chat_id}, status: {bot_member.status}")
                        return
                    
                    await context.bot.promote_chat_member(**promote_params)
                    
                    # Add to bot-promoted admins tracking
                    await db.add_bot_promoted_admin(chat_id, target_user_id, promoter_id)
                    
                    await query.answer("✅ تم رفع المشرف بكامل الصلاحيات المتاحة", show_alert=False)
                    await query.edit_message_text(
                        f"✅ تم رفع {session['target_name']} مشرفاً بكامل الصلاحيات المتاحة"
                    )
                    
                    # Clean up session
                    del promotion_sessions[chat_id][promoter_id]
                    
                    logger.info(f"User {target_user_id} promoted with all available bot permissions")
                    
                except Exception as e:
                    error_msg = str(e)
                    if "not enough rights" in error_msg.lower() or "insufficient" in error_msg.lower():
                        await query.answer("❌ البوت لا يملك صلاحيات كافية", show_alert=True)
                        logger.error(f"Bot lacks permissions to promote user: {e}")
                    else:
                        await query.answer("❌ فشل رفع المشرف", show_alert=True)
                        logger.error(f"Failed to promote user: {e}")
            else:
                await query.answer("❌ انتهت الجلسة", show_alert=True)
        
        elif data.startswith("promote_none_"):
            promoter_id = int(data.split("_")[-1])
            
            if chat_id in promotion_sessions and promoter_id in promotion_sessions[chat_id]:
                session = promotion_sessions[chat_id][promoter_id]
                target_user_id = session['target_user_id']
                chat_type = session.get('chat_type', 'supergroup')
                
                try:
                    # Promote with no permissions (all False)
                    if chat_type == 'channel':
                        await context.bot.promote_chat_member(
                            chat_id=chat_id,
                            user_id=target_user_id,
                            can_change_info=False,
                            can_post_messages=False,
                            can_edit_messages=False,
                            can_delete_messages=False,
                            can_invite_users=False,
                            can_manage_chat=False,
                            can_post_stories=False,
                            can_edit_stories=False,
                            can_delete_stories=False
                        )
                    else:
                        await context.bot.promote_chat_member(
                            chat_id=chat_id,
                            user_id=target_user_id,
                            can_change_info=False,
                            can_delete_messages=False,
                            can_invite_users=False,
                            can_restrict_members=False,
                            can_pin_messages=False,
                            can_promote_members=False,
                            can_manage_chat=False,
                            can_manage_video_chats=False
                        )
                    
                    # Add to bot-promoted admins tracking
                    await db.add_bot_promoted_admin(chat_id, target_user_id, promoter_id)
                    
                    await query.answer("✅ تم رفع المشرف بدون صلاحيات", show_alert=False)
                    await query.edit_message_text(
                        f"✅ تم رفع {session['target_name']} مشرفاً بدون صلاحيات"
                    )
                    
                    # Clean up session
                    del promotion_sessions[chat_id][promoter_id]
                    
                    logger.info(f"User {target_user_id} promoted with no permissions")
                    
                except Exception as e:
                    await query.answer("❌ فشل رفع المشرف", show_alert=True)
                    logger.error(f"Failed to promote user: {e}")
            else:
                await query.answer(" الرجاء اعادة المحاولة  ", show_alert=True)
        
        elif data.startswith("promote_custom_"):
            promoter_id = int(data.split("_")[-1])
            
            if chat_id in promotion_sessions and promoter_id in promotion_sessions[chat_id]:
                # Show custom permissions UI with bot's available permissions
                await show_permissions_ui(query, context, promoter_id, chat_id, is_query=True)
                await query.answer()
            else:
                await query.answer(" الرجاء اعادة المحاولة  ", show_alert=True)
        
        elif data.startswith("confirm_promote_"):
            logger.info(f"Confirm promote button pressed: {data}")
            promoter_id = int(data.split("_")[-1])
            
            logger.info(f"Looking for session: chat_id={chat_id}, promoter_id={promoter_id}")
            
            # Check if promoter has an active session
            if chat_id in promotion_sessions and promoter_id in promotion_sessions[chat_id]:
                session = promotion_sessions[chat_id][promoter_id]
                target_user_id = session['target_user_id']
                perms = session['permissions']
                chat_type = session.get('chat_type', 'supergroup')
                
                logger.info(f"Promoting user {target_user_id} in {chat_type} with permissions: {perms}")
                
                try:
                    # Build promotion parameters based on chat type
                    promote_params = {
                        'chat_id': chat_id,
                        'user_id': target_user_id
                    }
                    
                    # Add permissions based on what's available in the session
                    for perm_key, perm_value in perms.items():
                        if perm_key != 'chat_type':  # Skip non-permission keys
                            promote_params[perm_key] = perm_value
                    
                    # Promote user with selected permissions
                    await context.bot.promote_chat_member(**promote_params)
                    
                    # Add to bot-promoted admins tracking
                    await db.add_bot_promoted_admin(chat_id, target_user_id, promoter_id)
                    
                    # Answer callback first
                    await query.answer("✅ تم رفع المشرف بنجاح", show_alert=False)
                    
                    # Simple success message
                    await query.edit_message_text(
                        f"✅ تم رفع {session['target_name']} مشرفاً"
                    )
                    
                    # Clean up session
                    del promotion_sessions[chat_id][promoter_id]
                    
                    logger.info(f"User {target_user_id} promoted to admin with permissions in chat {chat_id}")
                    
                except Exception as e:
                    await query.answer("❌ فشل رفع المشرف", show_alert=True)
                    logger.error(f"Failed to promote user: {e}")
            else:
                logger.warning(f"No session found for confirm_promote: chat_id={chat_id}, promoter_id={promoter_id}")
                await query.answer("يرجى المحاولة مرة أخرى", show_alert=True)
        
        elif data.startswith("activate_protection_"):
            # Extract chat_id from callback data
            protection_chat_id = int(data.split("_")[-1])
            
            # Show full protection activation button
            keyboard = [
                [InlineKeyboardButton("🛡️", callback_data=f"enable_full_protection_{protection_chat_id}")]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await query.edit_message_text(
                "🔐 خيارات الحماية\n\n"
                "اضغط على الزر بالأسفل لتفعيل الحماية الكاملة:",
                reply_markup=reply_markup
            )
            await query.answer()
        
        elif data.startswith("enable_full_protection_"):
            # Extract chat_id from callback data
            protection_chat_id = int(data.split("_")[-1])
            
            # Enable full protection
            await db.enable_full_protection(protection_chat_id, user.id)
            
            await query.edit_message_text(
                "✅ تم تفعيل الحماية الكاملة بنجاح\n\n"
                "🛡️ الحماية النشطة:\n"
                "• منع أرقام الهواتف\n"
                "• منع الاقتباسات من القنوات\n"
                "• حظر القنوات والبوتات\n"
                "• منع التعديل\n"
                "• منع الروابط\n"
                "• منع جهات الاتصال\n"
                "• منع اللغة الإنجليزية والروسية"
            )
            await query.answer("✅ تم التفعيل", show_alert=False)
            logger.info(f"Full protection enabled for chat {protection_chat_id} by user {user.id}")
        
        elif data == "admin_global_owners":
            await handle_global_owners_panel(query, context)
        
        elif data == "admin_local_admins":
            await handle_local_admins_panel(query, context)
        
        elif data == "admin_protection_settings":
            await handle_protection_settings_panel(query, context)
        
        elif data.startswith("view_whisper_"):
            # View whisper
            whisper_id = int(data.split("_")[2])
            
            # Get whisper from database
            whisper = await db.get_whisper(whisper_id)
            
            if not whisper:
                await query.answer("خطا 🔴", show_alert=True)
                return
            
            w_id, w_chat_id, from_user_id, to_user_id, message, seen, group_message_id = whisper
            
            # Check if user is authorized (recipient, sender, developer, or global owner)
            is_authorized = (
                user.id == to_user_id or 
                user.id == from_user_id or
                user.id == DEVELOPER_ID or 
                await db.is_global_owner(user.id)
            )
            
            if not is_authorized:
                await query.answer("• الهمسة لاتخصك ", show_alert=True)
                return
            
            # Mark as seen if recipient is viewing
            if user.id == to_user_id and not seen:
                await db.mark_whisper_seen(whisper_id)
                
                # Notify sender that whisper was seen
                try:
                    recipient_info = await context.bot.get_chat(user.id)
                    recipient_name = recipient_info.full_name or recipient_info.username or str(user.id)
                    
                    await context.bot.send_message(
                        chat_id=from_user_id,
                        text=f"👁️ تم قراءة همستك من قبل {recipient_name}"
                    )
                except Exception as e:
                    logger.error(f"Failed to notify whisper sender: {e}")
            
            # Show whisper in alert popup (max 200 chars for Telegram alerts) - message only, no extra text
            whisper_preview = message[:180] + "..." if len(message) > 180 else message
            
            await query.answer(whisper_preview, show_alert=True)
            
            # If recipient is viewing, add reply button alongside view button
            if user.id == to_user_id:
                try:
                    # Reply should target the original sender (from_user_id), only to_user_id can reply
                    deep_link = f"https://t.me/{context.bot.username}?start=hms{w_chat_id}from_{from_user_id}_allow_{to_user_id}"
                    
                    # Get sender info for display
                    try:
                        sender_info = await context.bot.get_chat(from_user_id)
                        sender_name = escape_markdown(sender_info.full_name or sender_info.username or str(from_user_id), version=2)
                    except:
                        sender_name = escape_markdown(str(from_user_id), version=2)
                    
                    # Keep both buttons: view + reply
                    keyboard = [
                        [InlineKeyboardButton("رؤية الهمسة", callback_data=f"view_whisper_{whisper_id}")],
                        [InlineKeyboardButton("رد على الهمسة", url=deep_link)]
                    ]
                    reply_markup = InlineKeyboardMarkup(keyboard)
                    
                    await query.edit_message_text(
                        text=f"• ياحلو ↤ [{to_name}](tg://user?id={to_user.id})\n\n• وصلتك همسة سرية من ↤ ︎[{sender_name}](tg://user?id={user.id})\n\n• انت وحدك تقدر تشوفها",
                        reply_markup=reply_markup,
                        parse_mode='MarkdownV2'
                    )
                except Exception as e:
                    logger.error(f"Failed to update whisper message: {e}")
            
            logger.info(f"User {user.id} viewed whisper {whisper_id}")
        
        elif data.startswith("change_dev_"):
            new_dev_id = int(data.split("_")[2])
            await handle_developer_change(query, context, new_dev_id)
    
    except Exception as e:
        logger.error(f"Error handling callback query: {e}", exc_info=True)
        try:
            await query.answer("❌ حدث خطأ أثناء معالجة الطلب", show_alert=True)
        except:
            pass

async def handle_global_owners_panel(query, context: ContextTypes.DEFAULT_TYPE):
    """Handle global owners panel"""
    try:
        global_owners = await db.get_global_owners_list()
        
        text = "👑 **المالكين الأساسيين**\n\n"
        
        if global_owners:
            for owner in global_owners:
                user_id = owner[0]
                try:
                    user_info = await context.bot.get_chat(user_id)
                    name = user_info.full_name or user_info.username or str(user_id)
                    text += f"• {name} (ID: {user_id})\n"
                except:
                    text += f"• المستخدم {user_id}\n"
        else:
            text += "لا يوجد مالكين أساسيين حالياً"
        
        keyboard = [[InlineKeyboardButton(" • رجوع •", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text=text,
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logger.error(f"Error in global owners panel: {e}")

async def handle_local_admins_panel(query, context: ContextTypes.DEFAULT_TYPE):
    """Handle local admins panel"""
    try:
        # This would show admins from all groups - simplified for now
        text = "👮‍♂️ **إدارة الأدمنية المحليين**\n\n"
        text += "يمكنك رفع الأدمنية في المجموعات باستخدام:\n"
        text += "• الرد على رسالة المستخدم بـ `رفع ادمن`\n"
        text += "• استخدام أمر `/admins` لعرض قائمة الأدمنية في أي مجموعة"
        
        keyboard = [[InlineKeyboardButton("🔙 العودة للقائمة الرئيسية", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text=text,
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logger.error(f"Error in local admins panel: {e}")

async def handle_protection_settings_panel(query, context: ContextTypes.DEFAULT_TYPE):
    """Handle protection settings panel"""
    try:
        text = "🛡️ **إعدادات الحماية**\n\n"
        text += "الحماية الحالية تشمل:\n"
        text += "• ✅ حذف جهات الاتصال وكتم المرسل (50 دقيقة)\n"
        text += "• ✅ حذف أرقام الهواتف\n"
        text += "• ✅ حذف بيانات بطاقات الائتمان\n"
        text += "• ✅ حذف الروابط\n"
        text += "• ✅ حذف المحتوى المحظور\n"
        text += "• ✅ حذف الرسائل المكررة\n"
        text += "• ✅ حذف النصوص غير العربية\n"
        text += "• ✅ حذف الرسائل المعدلة\n\n"
        text += "🔧 جميع الإعدادات مفعلة ولا تحتاج تعديل"
        
        keyboard = [[InlineKeyboardButton(" • رجوع •", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            text=text,
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logger.error(f"Error in protection settings panel: {e}")

async def handle_developer_change(query, context: ContextTypes.DEFAULT_TYPE, new_dev_id: int):
    """Handle developer change request"""
    user = query.from_user
    
    try:
        # Check if user can change developer
        if user.id not in SUPER_ADMINS:
            await query.answer("❌ ليس لديك صلاحية لتغيير المطور", show_alert=True)
            return
        
        global DEVELOPER_ID
        old_dev = DEVELOPER_ID
        
        # Log the change
        await db.log_developer_change(old_dev, new_dev_id, user.id)
        
        # Update developer ID
        DEVELOPER_ID = new_dev_id
        
        await query.edit_message_text(
            f"✅ تم تغيير المطور بنجاح\n\n"
            f"المطور السابق: {old_dev}\n"
            f"المطور الجديد: {new_dev_id}\n"
            f"تم التغيير بواسطة: {user.id}"
        )
        
        # Notify both old and new developer
        try:
            await context.bot.send_message(
                chat_id=old_dev,
                text=f"⚠️ تم تغيير صلاحيات المطور\nالمطور الجديد: {new_dev_id}\nبواسطة: {user.id}"
            )
            await context.bot.send_message(
                chat_id=new_dev_id,
                text=f"🎉 تم منحك صلاحيات المطور\nبواسطة: {user.id}"
            )
        except Exception as e:
            logger.error(f"Failed to notify about developer change: {e}")
        
        logger.info(f"Developer changed from {old_dev} to {new_dev_id} by {user.id}")
        
    except Exception as e:
        logger.error(f"Error changing developer: {e}")
        await query.answer("❌ حدث خطأ أثناء تغيير المطور", show_alert=True)

# ---------- Admin Command Handlers ----------
async def handle_admins_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /admins command to show admin list"""
    if not update.message:
        return
    
    message = update.message
    user = message.from_user
    
    try:
        # Check if user is trusted or global owner
        if not (await db.is_trusted(message.chat_id, user.id) or 
                await db.is_global_owner(user.id) or 
                user.id == DEVELOPER_ID):
            return  # Silent mode: no response for unauthorized users
        
        # Get admins list
        admins = await db.get_admins_list(message.chat_id)
        
        if not admins:
            await message.reply_text("📝 لا يوجد أدمنية في هذه المجموعة")
            return
        
        admin_text = "👥 قائمة الأدمنية:\n\n"
        for admin in admins:
            user_id = admin[0]
            try:
                # Try to get user info
                admin_user = await context.bot.get_chat_member(message.chat_id, user_id)
                display_name = admin_user.user.full_name or admin_user.user.username or str(user_id)
                admin_text += f"• {display_name} (ID: {user_id})\n"
            except:
                admin_text += f"• المستخدم {user_id}\n"
        
        await message.reply_text(admin_text)
        
    except Exception as e:
        logger.error(f"Error handling admins command: {e}")
async def handle_reply_promotion(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle developer's reply to promote user to admin or global owner"""
    if not update.message or not update.message.reply_to_message:
        return

    message = update.message
    replied_message = message.reply_to_message
    developer = message.from_user
    target_user = replied_message.from_user if replied_message else None
    chat_id = message.chat_id

    # Check if it's a global owner or developer
    if not developer or not (await db.is_global_owner(developer.id) or developer.id == DEVELOPER_ID):
        return

    if not target_user:
        return

    try:
        text = message.text.strip() if message.text else ""
        
        if text == "رفع ادمن":
            # Add user to trusted list (local admin)
            await db.add_trusted_user(
                chat_id, 
                target_user.id, 
                developer.id
            )

            # Send confirmation
            await message.reply_text(
                f"✅ تم رفع {target_user.full_name or target_user.username or target_user.id} إلى أدمن"
            )

            # Log the promotion
            await db.log_action(
                chat_id,
                target_user.id,
                message.message_id,
                "PROMOTE_ADMIN",
                f"Promoted by {developer.id}"
            )

            logger.info(f"User {target_user.id} promoted to admin in chat {chat_id}")
        
        elif text == "رفع مالك اساسي" and developer.id == DEVELOPER_ID:
            # Add user to global owners (works across all groups)
            await db.add_global_owner(target_user.id, DEVELOPER_ID)
            GLOBAL_OWNERS.add(target_user.id)

            # Send confirmation
            await message.reply_text(
                f"👑 تم رفع {target_user.full_name or target_user.username or target_user.id} إلى مالك أساسي\n\n⚡ سيتم رفعه في جميع المجموعات"
            )

            # Log the promotion
            await db.log_action(
                chat_id,
                target_user.id,
                message.message_id,
                "PROMOTE_GLOBAL_OWNER",
                f"Promoted to global owner by {DEVELOPER_ID}"
            )

            logger.info(f"User {target_user.id} promoted to global owner")
        
        elif text == "رفع مشرف":
            # Initialize promotion session
            if chat_id not in promotion_sessions:
                promotion_sessions[chat_id] = {}
            
            # Get chat type to determine available permissions
            chat = await context.bot.get_chat(chat_id)
            chat_type = chat.type  # 'channel' or 'supergroup'
            
            # Default permissions based on chat type
            if chat_type == 'channel':
                # Channel permissions
                permissions = {
                    'can_change_info': False,
                    'can_post_messages': False,
                    'can_edit_messages': False,
                    'can_delete_messages': False,
                    'can_invite_users': False,
                    'can_manage_chat': False,
                    'can_post_stories': False,
                    'can_edit_stories': False,
                    'can_delete_stories': False,
                    'is_anonymous': False
                }
            else:
                # Supergroup permissions
                permissions = {
                    'can_change_info': False,
                    'can_delete_messages': False,
                    'can_invite_users': False,
                    'can_restrict_members': False,
                    'can_pin_messages': False,
                    'can_promote_members': False,
                    'can_manage_chat': False,
                    'can_manage_video_chats': False,
                    'is_anonymous': False
                }
            
            promotion_sessions[chat_id][developer.id] = {
                'target_user_id': target_user.id,
                'target_name': target_user.full_name or target_user.username or str(target_user.id),
                'chat_type': chat_type,
                'permissions': permissions
            }
            
            # Show promotion options (full, none, custom)
            await show_promotion_options(message, context, developer.id, target_user)
        
        elif text == "تنزيل مشرف":
            # Try to demote the admin
            try:
                # Check if user is actually an admin
                member = await context.bot.get_chat_member(chat_id, target_user.id)
                
                if member.status in ['administrator', 'creator']:
                    # Demote from Telegram admin
                    await context.bot.promote_chat_member(
                        chat_id=chat_id,
                        user_id=target_user.id,
                        can_delete_messages=False,
                        can_restrict_members=False,
                        can_promote_members=False,
                        can_change_info=False,
                        can_invite_users=False,
                        can_pin_messages=False,
                        can_manage_chat=False
                    )
                
                # Send confirmation
                await message.reply_text(
                    f"✅ تم تنزيل {target_user.full_name or target_user.username or target_user.id} من الإدارة"
                )
                
                logger.info(f"User {target_user.id} demoted in chat {chat_id}")
                
            except Exception as e:
                await message.reply_text("❌ فشل تنزيل المشرف")
                logger.error(f"Failed to demote admin: {e}")

    except Exception as e:
        logger.error(f"Error promoting user: {e}")

async def show_promotion_options(message, context: ContextTypes.DEFAULT_TYPE, promoter_id: int, target_user):
    """Show initial promotion options: full permissions, no permissions, or custom"""
    chat_id = message.chat_id
    session = promotion_sessions[chat_id][promoter_id]
    chat_type = session.get('chat_type', 'supergroup')
    
    keyboard = [
        [InlineKeyboardButton("🌟 كامل الصلاحيات", callback_data=f"promote_full_{promoter_id}")],
        [InlineKeyboardButton("⚪ بدون صلاحيات", callback_data=f"promote_none_{promoter_id}")],
        [InlineKeyboardButton("⚙️ مخصص", callback_data=f"promote_custom_{promoter_id}")]
    ]
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    chat_type_ar = "القناة" if chat_type == 'channel' else "المجموعة"
    await message.reply_text(
        f"👤 رفع مشرف: {session['target_name']}\n"
        f"📍 في: {chat_type_ar}\n\n"
        f"اختر نوع الصلاحيات:",
        reply_markup=reply_markup
    )

async def show_permissions_ui(query_or_message, context: ContextTypes.DEFAULT_TYPE, promoter_id: int, chat_id: int, is_query: bool = False):
    """Show permissions selection UI with bot's available permissions only"""
    session = promotion_sessions[chat_id][promoter_id]
    perms = session['permissions']
    chat_type = session.get('chat_type', 'supergroup')
    
    # Get bot's own permissions to filter available options
    try:
        from telegram import ChatMemberAdministrator, ChatMemberOwner
        bot_member = await context.bot.get_chat_member(chat_id, context.bot.id)
        bot_perms = {}
        
        # Check if bot is owner or admin to get permissions
        if isinstance(bot_member, ChatMemberOwner):
            # Owner has all permissions
            if chat_type == 'channel':
                bot_perms = {
                    'can_change_info': True,
                    'can_post_messages': True,
                    'can_edit_messages': True,
                    'can_delete_messages': True,
                    'can_invite_users': True,
                    'can_manage_chat': True,
                    'can_post_stories': True,
                    'can_edit_stories': True,
                    'can_delete_stories': True,
                }
            else:
                bot_perms = {
                    'can_change_info': True,
                    'can_delete_messages': True,
                    'can_invite_users': True,
                    'can_restrict_members': True,
                    'can_pin_messages': True,
                    'can_promote_members': True,
                    'can_manage_chat': True,
                    'can_manage_video_chats': True,
                }
        elif isinstance(bot_member, ChatMemberAdministrator):
            # Administrator - get actual permissions
            if chat_type == 'channel':
                bot_perms = {
                    'can_change_info': getattr(bot_member, 'can_change_info', False),
                    'can_post_messages': getattr(bot_member, 'can_post_messages', False),
                    'can_edit_messages': getattr(bot_member, 'can_edit_messages', False),
                    'can_delete_messages': getattr(bot_member, 'can_delete_messages', False),
                    'can_invite_users': getattr(bot_member, 'can_invite_users', False),
                    'can_manage_chat': getattr(bot_member, 'can_manage_chat', False),
                    'can_post_stories': getattr(bot_member, 'can_post_stories', False),
                    'can_edit_stories': getattr(bot_member, 'can_edit_stories', False),
                    'can_delete_stories': getattr(bot_member, 'can_delete_stories', False),
                }
            else:
                bot_perms = {
                    'can_change_info': getattr(bot_member, 'can_change_info', False),
                    'can_delete_messages': getattr(bot_member, 'can_delete_messages', False),
                    'can_invite_users': getattr(bot_member, 'can_invite_users', False),
                    'can_restrict_members': getattr(bot_member, 'can_restrict_members', False),
                    'can_pin_messages': getattr(bot_member, 'can_pin_messages', False),
                    'can_promote_members': getattr(bot_member, 'can_promote_members', False),
                    'can_manage_chat': getattr(bot_member, 'can_manage_chat', False),
                    'can_manage_video_chats': getattr(bot_member, 'can_manage_video_chats', False),
                }
        else:
            logger.warning(f"Bot is not admin in chat {chat_id}, cannot show permissions")
    except Exception as e:
        logger.error(f"Failed to get bot permissions: {e}")
        bot_perms = {}
    
    # Create permission buttons based on chat type
    keyboard = []
    
    if chat_type == 'channel':
        # Channel-specific permission labels
        perm_labels = {
            'can_change_info': 'تغيير المعلومات',
            'can_post_messages': 'نشر الرسائل',
            'can_edit_messages': 'تعديل الرسائل',
            'can_delete_messages': 'مسح الرسائل',
            'can_invite_users': 'اضافة الاعضاء',
            'can_manage_chat': 'إدارة القناة',
            'can_post_stories': 'نشر القصص',
            'can_edit_stories': 'تعديل القصص',
            'can_delete_stories': 'مسح القصص',
            'is_anonymous': 'مجهول الهوية'
        }
    else:
        # Supergroup-specific permission labels
        perm_labels = {
            'can_change_info': 'تغيير المعلومات',
            'can_delete_messages': 'مسح الرسائل',
            'can_invite_users': 'اضافة الاعضاء',
            'can_restrict_members': 'حظر المستخدمين',
            'can_pin_messages': 'تثبيت الرسائل',
            'can_promote_members': 'اضافة المشرفين',
            'can_manage_chat': 'إدارة المجموعة',
            'can_manage_video_chats': 'إدارة المكالمات',
            'is_anonymous': 'مجهول الهوية'
        }
    
    for perm_key, perm_label in perm_labels.items():
        # Only show permission if bot has it OR if it's is_anonymous (always available)
        if perm_key in perms and (bot_perms.get(perm_key, False) or perm_key == 'is_anonymous'):
            status = "✅" if perms[perm_key] else "⚠️"
            keyboard.append([
                InlineKeyboardButton(
                    f"{perm_label} ↤ {status}",
                    callback_data=f"perm_toggle_{perm_key}_{promoter_id}"
                )
            ])
    
    # Add confirmation button
    keyboard.append([
        InlineKeyboardButton(
            "رفعه مشرفاً ✅",
            callback_data=f"confirm_promote_{promoter_id}"
        )
    ])
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    chat_type_ar = "القناة" if chat_type == 'channel' else "المجموعة"
    text = (
        f"⚙️ تعديل الصلاحيات ({chat_type_ar})\n\n"
        f"👤 المستخدم: {session['target_name']}\n\n"
        f"اضغط على الصلاحيات لتفعيلها/تعطيلها:"
    )
    
    if is_query:
        await query_or_message.edit_message_text(text, reply_markup=reply_markup)
    else:
        await query_or_message.reply_text(text, reply_markup=reply_markup)

async def handle_my_chat_member(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle bot being added to a chat"""
    if not update.my_chat_member:
        return
    
    old_status = update.my_chat_member.old_chat_member.status
    new_status = update.my_chat_member.new_chat_member.status
    chat = update.my_chat_member.chat
    
    # Bot was just added to a group
    if old_status in ['left', 'kicked'] and new_status in ['member', 'administrator']:
        chat_id = chat.id
        chat_title = chat.title or "المجموعة"
        
        try:
            # Get bot's admin status
            bot_member = await context.bot.get_chat_member(chat_id, context.bot.id)
            
            # Check if bot has required permissions (at least can_delete_messages)
            if bot_member.status == 'administrator' and bot_member.can_delete_messages:
                # Bot has required permissions - send activation message
                keyboard = [
                    [InlineKeyboardButton("تفعيل 🔐", callback_data=f"activate_protection_{chat_id}")]
                ]
                reply_markup = InlineKeyboardMarkup(keyboard)
                
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=f"✅ تم تفعيل {chat_title}\n\n"
                         f"اضغط على الزر بالأسفل لتفعيل الحماية:",
                    reply_markup=reply_markup
                )
            else:
                # Bot doesn't have required permissions
                keyboard = [
                    [InlineKeyboardButton("أضفني لقروبك ➕", url=f"https://t.me/{context.bot.username}?startgroup=true")]
                ]
                reply_markup = InlineKeyboardMarkup(keyboard)
                
                await context.bot.send_message(
                    chat_id=chat_id,
                    text="⚠️ لم تقم برفع البوت بكافة الصلاحيات\n\n"
                         "يرجى إضافة البوت كمشرف مع جميع الصلاحيات للحصول على الحماية الكاملة.",
                    reply_markup=reply_markup
                )
                
                # Leave the group after 5 seconds
                await asyncio.sleep(5)
                await context.bot.leave_chat(chat_id)
                logger.info(f"Left chat {chat_id} ({chat_title}) due to insufficient permissions")
                
        except Exception as e:
            logger.error(f"Error handling bot addition to chat: {e}")

async def handle_chat_member_update(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Monitor chat member updates to detect admin violations"""
    if not update.chat_member:
        return
    
    chat_id = update.chat_member.chat.id
    admin_user = update.chat_member.from_user
    old_status = update.chat_member.old_chat_member
    new_status = update.chat_member.new_chat_member
    
    if not admin_user or not old_status or not new_status:
        return
    
    try:
        # Check if the admin is bot-promoted
        if not await db.is_bot_promoted_admin(chat_id, admin_user.id):
            return
        
        # Detect if a member was banned/kicked
        if old_status.status in ['member', 'restricted'] and new_status.status in ['kicked', 'banned']:
            # Admin banned someone - demote them
            logger.info(f"Bot-promoted admin {admin_user.id} banned a user in chat {chat_id}. Demoting...")
            
            try:
                # Demote the admin (disable ALL possible permissions)
                await context.bot.promote_chat_member(
                    chat_id=chat_id,
                    user_id=admin_user.id,
                    can_delete_messages=False,
                    can_restrict_members=False,
                    can_promote_members=False,
                    can_change_info=False,
                    can_invite_users=False,
                    can_pin_messages=False,
                    can_manage_chat=False,
                    can_manage_video_chats=False,
                    can_manage_topics=False,
                    can_post_messages=False,
                    can_edit_messages=False,
                    can_post_stories=False,
                    can_edit_stories=False,
                    can_delete_stories=False,
                    is_anonymous=False
                )
                
                # Remove from tracking
                await db.remove_bot_promoted_admin(chat_id, admin_user.id)
                
                # Notify in the group
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=f"⚠️ تم تنزيل [{admin_user.full_name or admin_user.username or admin_user.id}](tg://user?id={admin_user.id}) من الإدارة\n\nالسبب: قام بحظر عضو",
                    parse_mode='Markdown'
                )
                
                logger.info(f"Admin {admin_user.id} demoted for banning user in chat {chat_id}")
            except Exception as e:
                logger.error(f"Failed to demote admin for banning: {e}")
        
        # Detect if someone was promoted to admin
        elif old_status.status in ['member', 'left'] and new_status.status in ['administrator']:
            # Check if the promoted user is a bot or if multiple admins were added
            if new_status.user.is_bot or admin_user.id != DEVELOPER_ID:
                logger.info(f"Bot-promoted admin {admin_user.id} added a new admin/bot in chat {chat_id}. Demoting both...")
                
                try:
                    # First, demote the newly added admin/bot (disable ALL possible permissions)
                    await context.bot.promote_chat_member(
                        chat_id=chat_id,
                        user_id=new_status.user.id,
                        can_delete_messages=False,
                        can_restrict_members=False,
                        can_promote_members=False,
                        can_change_info=False,
                        can_invite_users=False,
                        can_pin_messages=False,
                        can_manage_chat=False,
                        can_manage_video_chats=False,
                        can_manage_topics=False,
                        can_post_messages=False,
                        can_edit_messages=False,
                        can_post_stories=False,
                        can_edit_stories=False,
                        can_delete_stories=False,
                        is_anonymous=False
                    )
                    logger.info(f"Demoted newly added admin/bot {new_status.user.id}")
                    
                    # Then, demote the violating admin (disable ALL possible permissions)
                    await context.bot.promote_chat_member(
                        chat_id=chat_id,
                        user_id=admin_user.id,
                        can_delete_messages=False,
                        can_restrict_members=False,
                        can_promote_members=False,
                        can_change_info=False,
                        can_invite_users=False,
                        can_pin_messages=False,
                        can_manage_chat=False,
                        can_manage_video_chats=False,
                        can_manage_topics=False,
                        can_post_messages=False,
                        can_edit_messages=False,
                        can_post_stories=False,
                        can_edit_stories=False,
                        can_delete_stories=False,
                        is_anonymous=False
                    )
                    
                    # Remove from tracking
                    await db.remove_bot_promoted_admin(chat_id, admin_user.id)
                    
                    # Notify in the group
                    admin_type = "بوت" if new_status.user.is_bot else "مشرف"
                    
                    # Build notification message without markdown-sensitive data
                    notification = (
                        f"⚠️ تم تنزيل [{admin_user.full_name or admin_user.username or admin_user.id}](tg://user?id={admin_user.id}) من الإدارة\n\n"
                        f"السبب: قام بإضافة {admin_type}\n\n"
                        f"✅ تم تنزيل ال{admin_type} المضاف أيضاً"
                    )
                    
                    await context.bot.send_message(
                        chat_id=chat_id,
                        text=notification,
                        parse_mode='Markdown'
                    )
                    
                    logger.info(f"Admin {admin_user.id} and newly added admin/bot {new_status.user.id} demoted in chat {chat_id}")
                except Exception as e:
                    logger.error(f"Failed to demote admin for adding admin: {e}")
    
    except Exception as e:
        logger.error(f"Error in chat_member_update handler: {e}")

# ---------- Application Setup ----------
def main():
    """Main application entry point"""
    try:
        # Initialize database (synchronous)
        logger.info("Initializing database...")

        # Build application
        app = ApplicationBuilder().token(TOKEN).build()

        # Add message handlers (order matters - most specific first)
        
        # Handle callback queries first (buttons)
        app.add_handler(CallbackQueryHandler(handle_callback_query))
        
        # Handle start command
        app.add_handler(CommandHandler("start", handle_start_command))
        
        # Handle admin panel command (developer only)
        app.add_handler(CommandHandler("panel", handle_admin_panel))
        
        # Handle statistics command (developer only)
        app.add_handler(MessageHandler(
            filters.TEXT & filters.Regex(r'^الاحصائيات$'),
            handle_statistics_command
        ))
        
        # Handle developer promotion replies
        app.add_handler(MessageHandler(
            filters.REPLY & filters.TEXT & filters.Regex(r'^(رفع ادمن|رفع مالك اساسي|رفع مشرف|تنزيل مشرف)$'),
            handle_reply_promotion
        ))
        
        # Handle whisper requests
        app.add_handler(MessageHandler(
            filters.REPLY & filters.TEXT & filters.Regex(r'^(اهمس|همسه|همسة|ه)$'),
            handle_whisper_request
        ))
        
        # Handle admins command
        app.add_handler(CommandHandler("admins", handle_admins_command))
        
        # Handle chat member updates for admin monitoring
        app.add_handler(ChatMemberHandler(handle_chat_member_update, ChatMemberHandler.CHAT_MEMBER))
        
        # Handle bot being added/removed from chats
        app.add_handler(ChatMemberHandler(handle_my_chat_member, ChatMemberHandler.MY_CHAT_MEMBER))

        # Handle regular messages (should be last)
        app.add_handler(MessageHandler(
            filters.ALL & (~filters.UpdateType.EDITED_MESSAGE) & (~filters.COMMAND),
            handle_message
        ))

        # Handle edited messages
        app.add_handler(MessageHandler(
            filters.UpdateType.EDITED_MESSAGE,
            handle_edited_message
        ))

        logger.info("🤖 Advanced Telegram Moderator Bot started successfully")
        logger.info(f"👨‍💻 Developer ID: {DEVELOPER_ID}")
        logger.info("🔇 Running in silent mode")

        # Start polling
        app.run_polling(
            allowed_updates=["message", "edited_message", "chat_member", "my_chat_member", "callback_query"]
        )

    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    except Exception as e:
        # Security fix: Don't log the actual token, mask it
        error_msg = str(e)
        if TOKEN in error_msg:
            error_msg = error_msg.replace(TOKEN, "***MASKED_TOKEN***")
        logger.error(f"Bot crashed: {error_msg}")
        raise

if __name__ == "__main__":
    main()
