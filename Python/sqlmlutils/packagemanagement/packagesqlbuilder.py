from sqlmlutils.sqlbuilder import SQLBuilder
from sqlmlutils.packagemanagement.scope import Scope


class CreateLibraryBuilder(SQLBuilder):

    def __init__(self, pkg_name: str, pkg_filename: str, scope: Scope):
        self._name = clean_library_name(pkg_name)
        self._filename = pkg_filename
        self._has_params = True
        self._scope = scope

    @property
    def params(self):
        with open(self._filename, "rb") as f:
            pkgdatastr = "0x" + f.read().hex()

        installcheckscript = """
import os
import re
_ENV_NAME_USER_PATH = "MRS_EXTLIB_USER_PATH"
_ENV_NAME_SHARED_PATH = "MRS_EXTLIB_SHARED_PATH"


def _is_dist_info_file(name, file):
    return re.match(name + r"-.*egg", file) or re.match(name + r"-.*dist-info", file)


def _is_package_match(package_name, file):
    package_name = package_name.lower()
    file = file.lower()
    return file == package_name or file == package_name + ".py" or \
           _is_dist_info_file(package_name, file) or \
           ("-" in package_name and
            (package_name.split("-")[0] == file or _is_dist_info_file(package_name.replace("-", "_"), file)))

def package_files_in_scope(scope="private"):
    envdir = _ENV_NAME_SHARED_PATH if scope == "public" or os.environ.get(_ENV_NAME_USER_PATH, "") == "" \
        else _ENV_NAME_USER_PATH
    path = os.environ.get(envdir, "")
    if os.path.isdir(path):
        return os.listdir(path)
    return []

def package_exists_in_scope(sql_package_name: str, scope=None) -> bool:
    if scope is None:
        # default to user path for every user but DBOs
        scope = "public" if (os.environ.get(_ENV_NAME_USER_PATH, "") == "") else "private"
    package_files = package_files_in_scope(scope)
    return any([_is_package_match(sql_package_name, package_file) for package_file in package_files])

        
assert package_exists_in_scope("{sqlpkgname}", "{scopestr}")
""".format(sqlpkgname=self._name, scopestr=self._scope._name)

        return pkgdatastr, installcheckscript

    @property
    def base_script(self) -> str:
        return """         
-- Drop the library if it exists
BEGIN TRY
DROP EXTERNAL LIBRARY [{sqlpkgname}] {authorization}
END TRY
BEGIN CATCH
END CATCH

-- Parameter bind the package data
DECLARE @content varbinary(MAX) = convert(varbinary(MAX), %s, 1);
        
-- Create the library
CREATE EXTERNAL LIBRARY [{sqlpkgname}] {authorization}
FROM (CONTENT = @content) WITH (LANGUAGE = 'Python');

-- Dummy SPEES
{dummy_spees}

-- Check to make sure the package was installed
BEGIN TRY
    exec sp_execute_external_script
    @language = N'Python',
    @script = %s
    print('Package successfully installed.')
END TRY
BEGIN CATCH
    print('Package installation failed.');
    THROW;
END CATCH
""".format(sqlpkgname=self._name,
           authorization=_get_authorization(self._scope),
           dummy_spees=_get_dummy_spees())


class DropLibraryBuilder(SQLBuilder):

    def __init__(self, sql_package_name: str, scope: Scope):
        self._name = clean_library_name(sql_package_name)
        self._scope = scope

    @property
    def base_script(self) -> str:
        return """
DROP EXTERNAL LIBRARY [{}] {authorization}

{dummy_spees}
""".format(self._name, authorization=_get_authorization(self._scope), dummy_spees=_get_dummy_spees())


def clean_library_name(pkgname: str):
    return pkgname.replace("-", "_").lower()


def _get_authorization(scope: Scope) -> str:
    return "AUTHORIZATION dbo" if scope == Scope.public_scope() else ""


def _get_dummy_spees() -> str:
    return """
exec sp_execute_external_script
@language = N'Python',
@script = N''
"""
