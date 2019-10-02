# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from sqlmlutils.packagemanagement.scope import Scope
import os
import re

_ENV_NAME_USER_PATH = "MRS_EXTLIB_USER_PATH"
_ENV_NAME_SHARED_PATH = "MRS_EXTLIB_SHARED_PATH"

def show_installed_packages():
    import pkg_resources
    return [(d.project_name, d.version) for d in pkg_resources.working_set]

def get_server_info():
    from distutils.version import LooseVersion
    import pip
    if LooseVersion(pip.__version__) > LooseVersion("10"):
        from pip._internal import pep425tags
    else:
        from pip import pep425tags
    return {
        "impl_version_info": pep425tags.get_impl_version_info(),
        "abbr_impl": pep425tags.get_abbr_impl(),
        "abi_tag": pep425tags.get_abi_tag(),
        "platform": pep425tags.get_platform()
    }


def check_package_install_success(sql_package_name: str) -> bool:
    return package_exists_in_scope(sql_package_name)


def package_files_in_scope(scope=Scope.private_scope()):
    envdir = _ENV_NAME_SHARED_PATH if scope == Scope.public_scope() or os.environ.get(_ENV_NAME_USER_PATH, "") == "" \
        else _ENV_NAME_USER_PATH
    path = os.environ.get(envdir, "")
    if os.path.isdir(path):
        return os.listdir(path)
    return []


def package_exists_in_scope(sql_package_name: str, scope=None) -> bool:
    if scope is None:
        # default to user path for every user but DBOs
        scope = Scope.public_scope() if (os.environ.get(_ENV_NAME_USER_PATH, "") == "") else Scope.private_scope()
    package_files = package_files_in_scope(scope)
    return any([_is_package_match(sql_package_name, package_file) for package_file in package_files])


def _is_dist_info_file(name, file):
    return re.match(name + r'-.*egg', file) or re.match(name + r'-.*dist-info', file)


def _is_package_match(package_name, file):
    package_name = package_name.lower()
    file = file.lower()
    return file == package_name or file == package_name + ".py" or \
           _is_dist_info_file(package_name, file) or \
           ("-" in package_name and
            (package_name.split("-")[0] == file or _is_dist_info_file(package_name.replace("-", "_"), file)))



