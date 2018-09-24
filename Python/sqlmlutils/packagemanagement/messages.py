def no_upgrade(pkgname: str, serverversion: str, pkgversion: str = ""):
    return """
Package {pkgname} exists on server. Set upgrade to True to force upgrade.".format(pkgname))
The version of {pkgname} you are trying to install is {pkgversion}.
The version installed on the server is {serverversion}
    """.format(pkgname=pkgname, pkgversion=pkgversion, serverversion=serverversion)


def install(pkgname: str, version: str, targetpackage: bool):
    target = "target package" if targetpackage else "required dependency"
    return "Installing {} {} version {}".format(target, pkgname, version)
