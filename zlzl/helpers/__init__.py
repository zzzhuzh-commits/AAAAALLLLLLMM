from . import fonts
from .aiohttp_helper import AioHttp
from .utils import *

flag = True
retry_count = 0

while flag:
    try:
        from .chatbot import *
        from .functions import *
        from .memeifyhelpers import *
        from .progress import *
        from .qhelper import process
        from .tools import *

        break

    except ModuleNotFoundError as e:
        pkg = "Pillow" if e.name == "PIL" else e.name
        install_pip(pkg)

        retry_count += 1
        if retry_count > 5:
            break
