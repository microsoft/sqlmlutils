# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(methods)
library(testthat)

options(keep.source = TRUE)
Sys.setenv(TZ='GMT')

Driver <- Sys.getenv("DRIVER")
if (Driver == '') Driver <- "SQL Server"

Server <- Sys.getenv("SERVER")
if (Server == '') Server <- "."

Database <- Sys.getenv("DATABASE")
if (Database == '') Database <- "AirlineTestDB"

Uid <- Sys.getenv("USER")
Pwd <- Sys.getenv("PASSWORD")
PwdRevoTester <- Sys.getenv("PASSWORD_REVO_TESTER")
PwdPkgPrivateExtLib <- Sys.getenv("PASSWORD_PKG_PRIVATE_EXT_LIB")
if(Uid == '') Uid = NULL
if(Pwd == '') Pwd = NULL
if(PwdRevoTester == '') PwdRevoTester = NULL
if(PwdPkgPrivateExtLib == '') PwdPkgPrivateExtLib = NULL

sqlcmd_path <- Sys.getenv("SQLCMD")
if (sqlcmd_path == '') sqlcmd_path <- "sqlcmd"

cnnstr <- connectionInfo(driver=Driver, server=Server, database=Database, uid=Uid, pwd=Pwd)

testthatDir <- getwd()
R_Root <- file.path(testthatDir, "../..")
scriptDirectory <- file.path(testthatDir, "scripts")

repos <- getOption("repos")
if(is.null(repos) || length(repos) == 0){
    options(repos = "https://cran.microsoft.com")
}
cat("INFO: repos = ", getOption("repos"))

TestArgs <- list(
    # Compute context specifications
    gitRoot = R_Root,
    testDirectory = testthatDir,
    scriptDirectory = scriptDirectory,
    driver=Driver,
    server=Server,
    database=Database,
    uid=Uid, 
    pwd=Pwd,
    pwdRevoTester = PwdRevoTester,
    pwdPkgPrivateExtLib = PwdPkgPrivateExtLib,
    connectionString = cnnstr,
    sqlcmd = sqlcmd_path
)

options(TestArgs = TestArgs)
rm(TestArgs)
