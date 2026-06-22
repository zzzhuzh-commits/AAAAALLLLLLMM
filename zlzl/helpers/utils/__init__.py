from .extdl import *
from .paste import *

flag = True
check = 0
while flag:
    try:
        from . import format as _format
        from . import tools as _zedtools
        from . import utils as _zedutils
        from .events import *
        from .format import *
        from .tools import *
        from .utils import *

        break

    except ModuleNotFoundError as e:
        pkg = "Pillow" if e.name == "PIL" else e.name
        install_pip(pkg)

        check += 1
        if check > 5:
            break
