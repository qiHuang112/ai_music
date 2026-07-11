// 公共js文件

function jAlert(content, type = "red", bDismiss = false, config = {}) {
    let jConfig = {
        title: false, content: content, closeIcon: true, type: type, typeAnimated: true, backgroundDismiss: bDismiss, buttons: {
            ok: {
                text: '确定', btnClass: 'btn-blue'
            }
        }
    };
    return $.alert(Object.assign({}, jConfig, config));
}

function is_qq_wx_tb() {
    var ua = navigator.userAgent.toLowerCase();
    if (ua.match(/MicroMessenger\/[0-9]/i)) {
        jAlert("微信进入的用户请换用系统自带浏览器重新打开本站才能进行歌曲下载");
        return true;
    }

    if (ua.match(/QQ\/[0-9]/i)) {
        jAlert("QQ进入的用户请换用系统自带浏览器重新打开本站才能进行歌曲下载");
        return true;
    }

    if (ua.match(/tieba\/[0-9]/i)) {
        jAlert("百度贴吧进入的用户请换用系统自带浏览器重新打开本站才能进行歌曲下载");
        return true;
    }
    return false;
}


//收藏本站
function addFavorite(title, url) {
    try {
        window.external.addFavorite(url, title);
    } catch (e) {
        try {
            window.sidebar.addPanel(title, url, "");
        } catch (e) {
            alert("抱歉，您所使用的浏览器无法完成此操作。\n\n加入收藏失败，请使用 Ctrl+D 进行添加");
        }
    }
}
