# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from distutils.version import LooseVersion
import pip
import warnings
import sys

pipversion = LooseVersion(pip.__version__ )

if pipversion >= LooseVersion("19.3"):
    from pip._internal import pep425tags
    from pip._internal.main import main as pipmain
elif pipversion > LooseVersion("10"):
    from pip._internal import pep425tags
    from pip._internal import main as pipmain
else:
    if pipversion < LooseVersion("8.1.2"):
        warnings.warn("Pip version less than 8.1.2 not supported.", Warning)
    from pip import pep425tags
    from pip import main as pipmain

# Monkey patch the pip version information with server information
pep425tags.is_manylinux2010_compatible = lambda: True
pep425tags.is_manylinux1_compatible = lambda: True
pep425tags.get_impl_version_info = lambda: eval(sys.argv[1])
pep425tags.get_abbr_impl = lambda: sys.argv[2]
pep425tags.get_abi_tag = lambda: sys.argv[3]
pep425tags.get_platform = lambda: sys.argv[4]

# Call pipmain with the download request
pipmain(list(map(str.strip, sys.argv[5].split(","))))
