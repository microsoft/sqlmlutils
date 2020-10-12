# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import os
import re

from sqlmlutils.packagemanagement.scope import Scope

def show_installed_packages():
    import pkg_resources
    return [(d.project_name, d.version) for d in pkg_resources.working_set]

def get_server_info():
    from distutils.version import LooseVersion
    import pip
    pipversion = LooseVersion(pip.__version__)

    if pipversion >= LooseVersion("19.3"):
        from wheel import pep425tags
    elif pipversion > LooseVersion("10"):
        from pip._internal import pep425tags
    else:
        from pip import pep425tags
    return {
        "impl_version_info": pep425tags.get_impl_version_info(),
        "abbr_impl": pep425tags.get_abbr_impl(),
        "abi_tag": pep425tags.get_abi_tag(),
        "platform": pep425tags.get_platform("")
    }