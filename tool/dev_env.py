"""Where the build and release scripts find tools on this machine.

Every value can be overridden by the environment variable of the same name;
the defaults describe the maintainer's Mac relative to the home folder, so
no absolute personal path lives in the scripts themselves.
"""
import os
from pathlib import Path

HOME = Path.home()


def _setting(name, default):
    return os.environ.get(name) or str(default)


FLUTTER_BIN = _setting('FLUTTER_BIN', HOME / 'ClaudeProject/tools/flutter/bin/flutter')
ANDROID_HOME = Path(_setting('ANDROID_HOME', HOME / 'Library/Android/sdk'))
JAVA_HOME = _setting('JAVA_HOME', HOME / 'Library/Java/JavaVirtualMachines/openjdk-22.0.1/Contents/Home')
RELEASES_ROOT = Path(_setting('AI_MUSIC_RELEASES', HOME / 'ClaudeProject/releases/ai_music'))
LAN_UPDATE_SERVER = _setting('AI_MUSIC_LAN_SERVER', 'http://192.168.31.167:8788')
