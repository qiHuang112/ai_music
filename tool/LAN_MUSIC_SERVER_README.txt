AI Music 局域网音乐服务
========================

要求：Windows Python 3.9 或更高版本，不需要 Dart、Flutter 或第三方 Python 包。

直接启动：
  py -3 tool\lan_music_server.py --root E:\music --host 0.0.0.0 --port 8787

PowerShell 一键启动：
  powershell -ExecutionPolicy Bypass -File tool\start_lan_music_server.ps1

健康检查：
  http://192.168.31.57:8787/api/v1/health

服务只读，仅提供健康状态、音乐清单和文件下载，不提供上传或删除。
服务没有身份认证，0.0.0.0 会监听所有网卡；仅在受信任的家庭局域网运行，
只共享专用音乐目录，不要共享用户主目录或敏感文件，不要配置公网端口转发。
Windows 防火墙需要允许局域网子网访问 TCP 8787。管理员 PowerShell 可执行：
  New-NetFirewallRule -DisplayName 'AI Music LAN Music 8787' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8787 -RemoteAddress LocalSubnet -Profile Private
