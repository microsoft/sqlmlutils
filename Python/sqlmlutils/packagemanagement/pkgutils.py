import pkginfo
import os
import re


def _get_pkginfo(filename: str):
    try:
        if ".whl" in filename:
            return pkginfo.Wheel(filename)
        else:
            return pkginfo.SDist(filename)
    except Exception:
        return None


def get_package_name_from_file(filename: str) -> str:
    pkg = _get_pkginfo(filename)
    if pkg is not None and pkg.name is not None:
        return pkg.name
    name = os.path.splitext(os.path.basename(filename))[0]
    return re.sub(r"\-[0-9].*", "", name)


def get_package_version_from_file(filename: str):
    pkg = _get_pkginfo(filename)
    if pkg is not None and pkg.version is not None:
        return pkg.version
    return None

