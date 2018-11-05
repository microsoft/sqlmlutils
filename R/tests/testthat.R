# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(testthat)
library(sqlmlutils)

test_check("sqlmlutils", filter = "execute")
test_check("sqlmlutils", filter = "storedProcedure")
test_check("sqlmlutils", filter = "basic")
test_check("sqlmlutils", filter = "createExternal")
test_check("sqlmlutils", filter = "dependencies")
test_check("sqlmlutils", filter = "scope")
test_check("sqlmlutils", filter = "toplevel")
test_check("sqlmlutils", filter = "unit")


