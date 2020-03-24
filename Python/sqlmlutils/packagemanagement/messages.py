# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

def no_upgrade(pkgname: str, serverversion: str, pkgversion: str = ""):
    return """
Package {pkgname} exists on server. Set upgrade to True in install to force upgrade.
The version of {pkgname} you are trying to install is {pkgversion}.
The version installed on the server is {serverversion}
    """.format(
        pkgname=pkgname,
        pkgversion=pkgversion,
        serverversion=serverversion
    )


def install(pkgname: str, version: str, targetpackage: bool):
    target = "target package" if targetpackage else "required dependency"
    return "Installing {target} {pkgname} version {version}".format(
        target=target,
        pkgname=pkgname,
        version=version
    )
