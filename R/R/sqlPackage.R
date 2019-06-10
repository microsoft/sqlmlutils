# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.


# max size in chars of the owner parameter to limit sql injection attacks
# (the owner is used in CREATE EXTERAL LIBRARY AUTHORIZATION)
MAX_OWNER_SIZE_CONST <- 128
IS_TOP_PACKAGE_MISSING <- -1L
install.env <- new.env()
local(g_scriptFile <- NULL,env=install.env)

#' sql_installed.packages
#'
#' @description  Enumerates the currently installed R packages on a SQL Server for the current database
#'
#' @param connectionString ODBC connection string to Microsoft SQL Server database.
#' @param priority character vector or NULL (default). If non-null, used to select packages; "high" is equivalent to c("base", "recommended"). To select all packages without an assigned priority use priority = "NA".
#' @param noCache logical. If TRUE, do not use cached information, nor cache it.
#' @param fields a character vector giving the fields to extract from each package's DESCRIPTION file, or NULL. If NULL, the following fields are used: "Package", "LibPath", "Version", "Priority", "Depends", "Imports", "LinkingTo", "Suggests", "Enhances", "License", "License_is_FOSS", "License_restricts_use", "OS_type", "MD5sum", "NeedsCompilation", and "Built". Unavailable fields result in NA values.
#' @param subarch character string or NULL. If non-null and non-empty, used to select packages which are installed for that sub-architecture
#' @param scope character string which can be "private" or "public".
#' @param owner character string of a user whose private packages shall be listed (availableto dbo or db_owner users only)
#' @param scriptFile character string - a file where to record the tsql that is run by the function.
#' @return matrix with enumerated packages
#'
#'@seealso{
#'\code{\link{sql_install.packages}} to install packages
#'
#'\code{\link{sql_remove.packages}} to remove packages
#'
#'\code{\link{installed.packages}} for the base version of this function
#'
#'}
#' @export
sql_installed.packages <- function(connectionString,
                                   priority = NULL, noCache = FALSE, fields = "Package",
                                   subarch = NULL, scope = "private", owner = '',
                                   scriptFile = NULL)
{
    assign("g_scriptFile", scriptFile, envir = install.env)
    enumResult <- NULL

    checkOwner(owner)
    checkConnectionString(connectionString)
    checkVersion(connectionString)
    scope <- normalizeScope(scope)

    enumResult <- list(packages = NULL, warnings = NULL, errors = NULL)
    enumResult <- sqlEnumPackages(
        connectionString = connectionString,
        owner = owner, scope = scope,
        priority = priority, fields = fields, subarch = subarch)

    if (!is.null(enumResult$errors)){
        stop(enumResult$errors, call. = FALSE)
    }

    if (!is.null(enumResult$warnings)){
        warning(enumResult$warnings, immediate. = TRUE, call. = FALSE)
    }

    enumResult <- enumResult$packages

    return(enumResult)
}


#' sql_install.packages
#' @description Installs R packages on a SQL Server database. Packages are downloaded on the client and then copied and installed to SQL Server into "public" and "private" folders. Packages in the "public" folders can be loaded by all database users running R script in SQL. Packages in the "private" folder can be loaded only by a single user. 'dbo' users always install into the "public" folder. Users who are members of the 'db_owner' role can install to both "public" and "private" folders. All other users can only install packages to their "private" folder.
#'
#' @param connectionString ODBC connection string to Microsoft SQL Server database.
#' @param pkgs character vector of the names of packages whose current versions should be downloaded from the repositories. If repos = NULL, a character vector of file paths of .zip files containing binary builds of packages. (http:// and file:// URLs are also accepted and the files will be downloaded and installed from local copies).
#' @param skipMissing logical. If TRUE, skips missing dependent packages for which otherwise an error is generated.
#' @param repos character vector, the base URL(s) of the repositories to use.Can be NULL to install from local files, directories.
#' @param verbose logical. If TRUE, more detailed information is given during installation of packages.
#' @param scope character string. Should be either "public" or "private". "public" installs the packages on per database public location on SQL server which in turn can be used (referred) by multiple different users. "private" installs the packages on per database, per user private location on SQL server which is only accessible to the single user.
#' @param owner character string. Should be either empty '' or a valid SQL database user account name. Only 'dbo' or users in 'db_owner' role for a database can specify this value to install packages on behalf of other users. A user who is member of the 'db_owner' group can set owner='dbo' to install on the "public" folder.
#' @param scriptFile character string - a file where to record the tsql that is run by the function.
#' @return invisible(NULL)
#'
#'@seealso{
#'\code{\link{sql_remove.packages}} to remove packages
#'
#'\code{\link{sql_installed.packages}} to enumerate the installed packages
#'
#'\code{\link{install.packages}} for the base version of this function
#'}
#'
#' @export
sql_install.packages <- function(connectionString,
                                 pkgs,
                                 skipMissing = FALSE, repos,
                                 verbose = getOption("verbose"), scope = "private", owner = '',
                                 scriptFile = NULL)
{
    assign("g_scriptFile", scriptFile, envir = install.env)
    checkOwner(owner)
    checkConnectionString(connectionString)
    serverVersion <- checkVersion(connectionString)
    sqlInstallPackagesExtLib(connectionString,
                             pkgs = pkgs,
                             skipMissing = skipMissing, repos = repos,
                             verbose = verbose, scope = scope, owner = owner,
                             serverVersion = serverVersion)

    return(invisible(NULL))
}

#' sql_remove.packages
#'
#' @description Removes R packages from a SQL Server database.
#'
#' @param connectionString ODBC connection string to SQL Server database.
#' @param pkgs character vector of names of the packages to be removed.
#' @param dependencies logical. If TRUE, does dependency resolution of the packages being removed and removes the dependent packages also if the dependent packages aren't referenced by other packages outside the dependency closure.
#' @param checkReferences logical. If TRUE, verifies there are no references to the dependent packages by other packages outside the dependency closure. Use FALSE to force removal of packages even when other packages depend on it.
#' @param verbose logical. If TRUE, more detailed information is given during removal of packages.
#' @param scope character string. Should be either "public" or "private". "public" removes the packages from a per-database public location on SQL Server which in turn could have been used (referred) by multiple different users. "private" removes the packages from a per-database, per-user private location on SQL Server which is only accessible to the single user.
#' @param owner character string. Should be either empty '' or a valid SQL database user account name. Only 'dbo' or users in 'db_owner' role for a database can specify this value to remove packages on behalf of other users. A user who is member of the 'db_owner' group can set owner='dbo' to remove packages from the "public" folder.
#' @param scriptFile character string - a file where to record the tsql that is run by the function.
#' @return invisible(NULL)
#'
#'@seealso{
#'\code{\link{sql_install.packages}} to install packages
#'
#'\code{\link{sql_installed.packages}} to enumerate the installed packages
#'
#'\code{\link{remove.packages}} for the base version of this function
#'
#'}
#'
#' @export
sql_remove.packages <- function(connectionString, pkgs, dependencies = TRUE, checkReferences = TRUE,
                                verbose = getOption("verbose"), scope = "private", owner = '',
                                scriptFile = NULL)
{
    assign("g_scriptFile", scriptFile, envir = install.env)
    checkOwner(owner)
    checkConnectionString(connectionString)
    checkVersion(connectionString)

    if (length(pkgs) == 0){
        stop("no packages provided to remove")
    }

    scope <- normalizeScope(scope)
    scopeint <- parseScope(scope)

    if (scope == "PUBLIC" && is.character(owner) && nchar(owner) >0)
    {
        stop(paste0("Invalid use of scope PUBLIC. Use scope 'PRIVATE' to remove packages for owner '", owner ,"'\n"), call. = FALSE)
    }

    if(verbose){
        write(sprintf("%s  Starting package removal on SQL server (%s)...", pkgTime(), connectionString), stdout())
    } else {
        write(sprintf("(package removal may take a few minutes, set verbose=TRUE for progress report)"), stdout())
    }

    pkgsToDrop <- NULL  # packages to drop from table and not found in library path
    pkgsToReport <- NULL # packages only found in library path, we hope sp_execute_external_script removes the package and the report on it

    #
    # get installed packages
    #
    if (verbose)
    {
        write(sprintf("%s  Enumerating installed packages on SQL server...", pkgTime()), stdout())
    }

    installedPackages <- sql_installed.packages(connectionString = connectionString, fields = NULL, scope = scope, owner =  owner, scriptFile = scriptFile)
    installedPackages <- data.frame(installedPackages, row.names = NULL, stringsAsFactors = FALSE)
    installedPackages <- installedPackages[installedPackages$Scope == scope,]

    #
    # check for missing packages in the library path
    #
    missingPackagesLib <- pkgs[!(pkgs %in% installedPackages$Package)]
    if (length(missingPackagesLib) > 0)
    {
        # check if package is also missing in the internal table
        tablePackages <- sqlEnumTable(connectionString, missingPackagesLib, owner, scopeint)
        missingPackages <- tablePackages[tablePackages$Package == missingPackagesLib & tablePackages$Found == FALSE,"Package",drop=FALSE]$Package

        if (length(missingPackages) > 0){
            stop(sprintf("Cannot find specified packages (%s) to remove from scope '%s'", paste(missingPackages, collapse = ', '), scope), call. = FALSE)
        }

        # if a package is only in the table we still want to drop external library it
        # (e.g. package may be failing to install after a create external library outside sqlmlutils)
        pkgsToDrop <- tablePackages[tablePackages$Package == missingPackagesLib & tablePackages$Found == TRUE,"Package",drop=FALSE]$Package
        pkgs <- pkgs[pkgs %in% installedPackages$Package]
    }

    #
    # get the dependent list of packages which is safe to remove
    #
    pkgsToUninstall <- getDependentPackagesToUninstall(pkgs, installedPackages = installedPackages,
                                                       dependencies = dependencies, checkReferences = checkReferences, verbose = verbose)

    if (is.null(pkgsToUninstall))
    {
        pkgs <- NULL
    }
    else
    {
        pkgs <- pkgsToUninstall$Package

        # check if packages to uninstall are in the table as well and be drop external library
        tablePackages <- sqlEnumTable(connectionString, pkgs, owner, scopeint)
        pkgsToReport <- tablePackages[tablePackages$Package == pkgs & tablePackages$Found == FALSE, "Package", drop=FALSE]$Package
        if (length(pkgsToReport) > 0)
        {
            # we know package is in the library path, but not in the table.
            # It may be scheduled to be removed with the next sp_execute_external_script call or
            # it may be failing to remove at all!
            # In any case we will track the package and report on its status to the caller
            pkgs <- pkgs[!(pkgs %in% pkgsToReport)]
        }

    }

    if (length(pkgs) > 0 || length(pkgsToDrop) > 0 || length(pkgsToReport) > 0)
    {
        if (verbose)
        {
            write(sprintf("%s  Uninstalling packages on SQL server (%s)...", pkgTime(), paste(c(pkgs, pkgsToDrop, pkgsToReport), collapse = ', ')), stdout())
        }

        sqlHelperRemovePackages(connectionString, pkgs, pkgsToDrop, pkgsToReport, scope, owner, verbose)
    }
    return(invisible(NULL))
}


#
# Executes a R function on a remote sql server
# using sp_execute_external_script
# This is a variation on execute in sql, with a few extra params
#
# @param connection  odbc connection string or a valid RODBC handle
#
# @param FUN   function to execute
# @param ...   parameters passed to FUN
#
# @param useRemoteFun by default inserts function definition as available on the client as text into sp_execute_external_script
# if TRUE uses function as available on the remote server
#
# @param asuser  calls sp_execute_external_script with EXECUTE AS USER 'asuser'
#
# @return data frame returned by FUN
#
sqlRemoteExecuteFun <- function(connection, FUN, ..., useRemoteFun = FALSE, asuser = NULL, includeFun = list())
{
    g_scriptFile <- local(g_scriptFile, install.env)
    if (class(connection) == "character"){
        if (nchar(connection) < 1){
            stop(paste0("Invalid connection string: ", connection), call. = FALSE)
        }
    } else if (class(connection) != "RODBC"){
        stop("Invalid connection string has to be a character string or RODBC handle", call. = FALSE)
    }

    if (is.character(asuser) && length(asuser) == 1){
        if (nchar(asuser) == 0){
            asuser <- NULL
        }
    } else {
        asuser <- NULL
    }

    # input processing and checking
    if (is.function(FUN)) {
        funName <- deparse(substitute(FUN))
    } else {
        if (!is.character(FUN))
            stop(paste("you must provide either a function object or a function"))
        funName <- FUN
        FUN <- match.fun(FUN)
    }

    #
    # captures the R code and formats it to be embedded in t-sql sp_execute_external_script
    #
    deparseforSql <- function(funName, fun)
    {
        # counts the number of spaces at the beginning of the string
        countSpacesAtBegin <- function(s) {
            p <- gregexpr("^ *", s)
            return(attr(p[[1]], "match.length"))
        }

        funBody <- deparse(fun)

        # add on the function definititon
        funBody[1] <- paste(funName, "<-", funBody[1], sep = " ")

        # escape single quotes and get rid of tabs
        funBody <- sapply(funBody, gsub, pattern = "\t", replacement = "  ")
        funBody <- sapply(funBody, gsub, pattern = "'", replacement = "''")

        # handle the case where the function's rcode was indented
        # more than 2 spaces and get rid of extra spaces.
        # otherwsise the resulting indentation of R code in TSQL
        # will depend on the indentation of the code in the R
        if (length(funBody) > 1)
        {
            # temporarily discard empty lines so they don't affect space counting
            no_empty_lines <- funBody[funBody != ""]

            # remove the first line (function declaration line) from no_empty_lines
            # and if the last line only contains a closing bracket align it with
            # the function declaration and remove as well
            if (grepl("^ *} *$", funBody[length(funBody)])) {
                funBody[length(funBody)] <- "}"
                no_empty_lines <- no_empty_lines[2:(length(no_empty_lines) - 1)]
            } else {
                no_empty_lines <- no_empty_lines[2:length(no_empty_lines)]
            }

            # find the minimum number of extra spaces
            extra_spaces <- min(sapply(no_empty_lines, countSpacesAtBegin)) - 2

            # remove extra spaces
            if (extra_spaces > 0) {
                for (i in 2:(length(funBody) - 1)) {
                    funBody[i] <- gsub(paste("^ {", extra_spaces,"}", sep = ""),
                                       "", funBody[i])
                }
            }
        }

        funText <- paste(funBody, collapse = "\n")

        return (funText)
    }


    # Define a function that will attempt to resolve the ellipsis arguments
    # passed into the rxElem function and return those elements in a (named) list.
    # For those elements that are not resolvable, leave them as promises to be
    # evaluated on the cluster. This scheme avoids, for example, the need to have
    # a particular package loaded locally in order to (locally) resolve symbols/data
    # that belong to that package. In this case, the packagesToLoad argument is expected
    # to name the package that is required to be loaded on the cluster nodes in order for
    # the promised symbols to be resolvable.
    tryEvalArgList <- function(...)
    {
        # Convert ellipsis arguments into a list of substituted values,
        # which will result in names, symbols, or language objects and
        # will avoid the evaluation.
        argListSubstitute <- as.list(substitute(list(...)))[-1L]

        # Now attempt to evaluate each argument. If we fail, then keep
        # argument value as a substituted value. These substituted values
        # essentially act as a promise and will be evaluated on the cluster.
        # If they also fail (re not resolvable) on the cluster, an error will
        # be returned.
        envir <- parent.frame(n = 2)
        sapply(argListSubstitute, function(x, envir)
        {
            res <- try(eval(x, envir = envir), silent = TRUE)
            if (!inherits(res, "try-error")) res else x
        }, envir = envir, simplify = FALSE)
    }

    argList <- tryEvalArgList(...)
    binArgList <- serialize(argList, NULL)
    binArgListCollapse <- paste0(binArgList, collapse = ";")

    script <- ""

    if (length(includeFun) > 0)
    {
        includeFunNames <- names(includeFun)
        if(length(includeFunNames) != length(includeFun)){
            stop("invalid parameter 'includeFun' requires matching function names to be specified in list", call. = FALSE)
        }
        for (i in seq_along(includeFun))
        {
            script <- paste0(script, "\n", deparseforSql(includeFunNames[[i]], includeFun[[i]]))
        }
    }

    if (!useRemoteFun)
    {
        funText <- deparseforSql(funName, FUN)
        script <- paste0(script, "\n", funText)
    }


    script <- paste0(script,
                     sprintf("
                             result <- NULL
                             funerror <- NULL
                             funwarnings <- NULL
                             output <- capture.output(try(
                             withCallingHandlers({
                             binArgList <- unlist(lapply(lapply(strsplit(\"%s\",\";\")[[1]], as.hexmode), as.raw))
                             argList <- as.list(unserialize(binArgList))
                             result <- do.call(%s, argList)
                             }, error = function(err) {
                             funerror <<- err$message
                             }, warning = function(warn) {
                             funwarnings <<- c(funwarnings, warn$message)
                             }
                            ), silent = TRUE
                            ))
                             serializedResult <- as.character(serialize(list(result, funerror, funwarnings, output), NULL))
                             OutputDataSet <- data.frame(serializedResult, stringsAsFactors = FALSE)[1]
                             ", binArgListCollapse, funName)
                            )

    query <- ""
    if (!is.null(asuser)){
        query <- paste0("EXECUTE AS USER = '", asuser, "';")
    }

    query <- paste0(query
                    ,"\nEXEC sp_execute_external_script"
                    ,"\n@language = N'R'"
                    ,"\n,@script = N'",script, "';"
   )

    if (!is.null(asuser)){
        query <- paste0(query, "\nREVERT;")
    }

    success <- FALSE
    error <- ""
    hodbc <- -1
    tryCatch({
        if (class(connection) == "character"){
            hodbc <- odbcDriverConnect(connection)
            if (hodbc == -1){
                error <- sprintf("failed to connect to sql server using connection string %s", connection)
                success <- FALSE
            }
        } else {
            hodbc <- connection
        }

        if(!is.null(g_scriptFile)) {
            callingFun = as.character(as.list(sys.call()))
            if("findPackages" %in% callingFun ||
               "utils::installed.packages" %in% callingFun) {
                cat(sprintf("-- Called from %s\n", callingFun[[1]]), file=g_scriptFile, append=TRUE)
                cat(query, file=g_scriptFile, append=TRUE)
                cat("\n", file=g_scriptFile, append=TRUE)
            }
        }

        sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)
        if (is.data.frame(sqlResult)){
            serializedResult <- sqlResult[[1]]
            success <- TRUE
        } else {
            # error happened, vector of string contains error messages
            error <- paste(sqlResult, sep = "\n")
            success <- FALSE
        }
    }, error = function(err) {
        success <<- FALSE
        error <<- err$message
    }, finally = {
        if (class(connection) == "character" && hodbc != -1){
            odbcClose(hodbc)
        }
    })

    if (success)
    {
        lst <- unserialize(unlist(lapply(lapply(as.character(serializedResult),as.hexmode), as.raw)))

        result <- lst[[1]]
        funerror <- lst[[2]]
        funwarnings <-lst[[3]]
        output <- lst[[4]]

        if (!is.null(output)){
            for(o in output) {
                cat(paste0(o,"\n"))
            }
        }

        if (!is.null(funwarnings)){
            for(w in funwarnings) {
                warning(w, call. = FALSE)
            }
        }

        if (!is.null(funerror)){
            stop(funerror, call. = FALSE)
        }

        return(result)
    }
    else
    {
        stop(error, call. = FALSE)
    }
}

checkOwner <- function(owner)
{
    if (!is.null(owner))
    {
        if (is.character(owner) && length(owner) == 1 && nchar(owner) <= MAX_OWNER_SIZE_CONST)
        {
            invisible(NULL)
        }
        else
        {
            stop(paste0("Invalid value for owner: ", owner ,"\n"), call. = FALSE)
        }
    }
}

getPackageTopMostAttributeFlag <- function()
{
    0x1
}

pkgTime <- function()
{
    # tz: ""= current time zone, "GMT" = UTC
    return (format(Sys.time(), "%Y-%m-%d %H:%M:%OS2", tz = ""))
}

checkConnectionString <- function(connectionString)
{
    if (!is.null(connectionString) && is.character(connectionString) && length(connectionString) == 1 && nchar(connectionString) > 0)
    {
        invisible(NULL)
    }
    else
    {
        stop(paste0("Invalid connection string: ", connectionString ,"\n"), call. = FALSE)
    }
}

checkOdbcHandle <- function(hodbc, connectionString)
{
    if (hodbc == -1){
        stop(sprintf("Failed to connect to sql server using connection string %s", connectionString, call. = FALSE))
    }
    invisible(NULL)
}

checkResult <- function( result, expectedResult, errorMessage)
{
    if (result != expectedResult){
        stop(errorMessage, call. = FALSE)
    }
    invisible(NULL)
}

#
# Removes fields if requested
#
processInstalledPackagesResult <- function(result, fields)
{
    if (!is.null(fields) && is.character(fields))
    {
        result <- result[, fields, drop = FALSE]
    }

    if ((!is.null(fields)) && ((fields == "Package") && is.null(dim(result))))
    {
        names(result) <- NULL
    }
    return(result)
}


#
# Returns
#   normalized string for string cope
#   scope input for anything else
#
normalizeScope <- function(scope)
{
    scopes <- c("PUBLIC", "PRIVATE", "SYSTEM")
    if (is.character(scope) && length(scope) == 1)
    {
        normScope <- toupper(scope)
        if (normScope == "SHARED"){
            normScope <- "PUBLIC"
        }
        if (normScope %in% scopes){
            return (normScope)
        }
    }

    stop(sprintf("Invalid scope argument value: %s", scope), call. = FALSE)
}

#
# Parses scope which can be an integer or string
# returns
#   0 for PUBLIC / SHARED
#   1 for PRIVATE
#   PUBLIC for 0
#   PRIVATE for 1
#
parseScope <- function(scope)
{

    scopes <- c(0L, 1L, 0L)
    names(scopes) <- c("PUBLIC", "PRIVATE", "SHARED")

    if ((is.integer(scope) || is.numeric(scope)) && (scope%%1==0))
    {
        if ((scope >= 0L) && (scope <= 1L))
        {
            scopeIndex <- scope + 1L
            parsedScope <- names(scopes)[scopeIndex]
        }
        else
        {
            stop("Invalid scope argument value.", call. = FALSE)
        }
    }
    else if (is.character(scope) && length(scope) == 1 && toupper(scope) %in% names(scopes))
    {
        parsedScope <- scopes[[toupper(scope)]]
    }
    else
    {
        stop("Invalid scope argument value.", call. = FALSE)
    }

    if (is.na(parsedScope))
    {
        stop("Invalid scope argument value.", call. = FALSE)
    }

    parsedScope
}

#
# Returns R version with major minor like 3.4, 3.5
#
getRversionContribFormat <- function()
{
    paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L], sep = ".")
}

#
# Returns List
#   $`sysname`
#   [1] "Windows"
#
#   $rversion
#   [1] "3.4"
#
getserverVersion <- function(connectionString)
{
    checkConnectionString(connectionString)

    getSysnameRversion <- function()
    {
        return (list(sysname = Sys.info()[['sysname']], rversion = getRversionContribFormat()))
    }

    serverVersion <- sqlRemoteExecuteFun(connectionString, getSysnameRversion, includeFun = list(getRversionContribFormat = getRversionContribFormat))

    return(serverVersion)
}

#
# Returns current sql user (the result of SELECT USER query)
# Returns NULL if query failed
#
sqlSelectUser <- function(connectionString)
{
    user <- ""
    query <- "SELECT USER;"

    hodbc <- odbcDriverConnect(connectionString)
    checkOdbcHandle(hodbc, connectionString)
    on.exit(odbcClose(hodbc), add = TRUE)

    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.data.frame(sqlResult))
    {
        user <- sqlResult[1,1]
    }
    else
    {
        user <- NULL
    }

    return (user)
}

#
# Checks if sql server supports package management based on create external library
# Returns list with version information
#
#   $`serverIsWindows`
#   [1] TRUE
#
#   $rversion
#   [1] "3.4"
#
checkVersion <- function(connectionString)
{
    serverVersion <- getserverVersion(connectionString)
    serverIsWindows <- serverVersion[['sysname']] == 'Windows'

    versionClass <- sqlCheckPackageManagementVersion(connectionString)

    if (is.character(versionClass) &&  versionClass == "ExtLib"){
        return (list(serverIsWindows = serverIsWindows, rversion = serverVersion[['rversion']]))
    } else {
        stop(paste0("SQL server does not support package management."), call. = FALSE)
    }
}


#
# Checks if sql server version supports package management
# Returns "ExtLib" if is supports external library ddl
#
# We support SQL Azure DB
#
# SQL Azure            12.0.2000.8
# SQL Server 2017      14.0.1000.169
#
# Note:
# Older version os SQL server are support by the legacy
# package management APIs in RevoScaleR:
#
# SQL Server 2016 SP1  13.0.4001.0
# SQL Server 2016      13.0.1601.5
#
#' @importFrom utils tail
sqlCheckPackageManagementVersion <- function(connectionString)
{
    versionClass <- NA
    force(connectionString)

    if(is.null(connectionString) || nchar(connectionString) == 0){
        stop("Invalid connectionString is null or empty")
    }

    version <- sqlPackageManagementVersion(connectionString)

    if (is.null(version) || is.na(version) || length(version) == 0)
    {
        stop("Invalid SQL version is null or empty", call. = FALSE)
    }

    if( ( (version[["serverType"]]=="azure" && version[["major"]] >= 12 ) || (version[["serverType"]]=="box" && version[["major"]] >= 15 )))
    {
        # server supports external library with DDLs
        versionClass <- "ExtLib"
    }
    else
    {
        stop(sprintf("The package management feature is not enabled for the current user or not supported on SQL Server version %s", paste(tail(version, -1), collapse='.')), call. = FALSE)
    }

    return(versionClass)
}

#
# Returns a list with the "azure" or "box" for the first element and the product version is the remaining elements
#
# Examples:
#   list( serverType = "azure", major = 12, minor = 0, build = 2000, revision = 8)
#   list( serverType = "box", major = 15, minor = 0, build = 400, revision = 107)
#
#' @importFrom utils tail
sqlPackageManagementVersion <- function(connectionString)
{
    force(connectionString)

    pmversion <- NULL

    serverProperties <- sqlServerProperties(connectionString)
    if (is.null(serverProperties)){
        stop(sprintf("Failed to get SQL version using connection string '%s'", connectionString ), call. = FALSE)
    }

    if(serverProperties[["edition"]] == "sql azure" && serverProperties[["engineEdition"]]==5)
    {
        # sql azure
        pmversion <- append(list(serverType = "azure"), tail(serverProperties, -2))
    }
    else
    {
        # sql box product
        pmversion <- append(list(serverType = "box"), tail(serverProperties, -2))
    }

    return (pmversion)
}

#
# Returns a list with the Edition, EngineEdition and product version as an integer vector
# NULL if it failed
# Strings will lowercased
# Examples: list( edition = "sql azure", engineEdition = 5, major = 12, minor = 0, build = 2000, revision = 8)
# Examples: list( edition = "enterprise edition (64-bit)", engineEdition = 3, major = 15, minor = 0, build = 400, revision = 107)
#
# References: https://docs.microsoft.com/en-us/sql/t-sql/functions/serverproperty-transact-sql
#             https://technet.microsoft.com/en-us/library/ms174396(v=sql.110).aspx
#             http://www.sqlservercentral.com/blogs/gorandalfs-sql-blog/2015/06/10/azure-sql-database-version-and-compatibility-level/
#
sqlServerProperties <- function(connectionString)
{
    serverProperties <- NULL

    query <- paste0("SELECT CAST(SERVERPROPERTY('Edition') AS nvarchar) AS Edition, CAST(SERVERPROPERTY('EngineEdition') AS nvarchar) AS EngineEdition, CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) AS ProductVersion")

    hodbc <- odbcDriverConnect(connectionString)
    checkOdbcHandle(hodbc, connectionString)
    on.exit(odbcClose(hodbc), add = TRUE)

    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.data.frame(sqlResult))
    {
        #
        #                      Edition EngineEdition ProductVersion
        #1 Enterprise Edition (64-bit)             3    15.0.800.91
        #
        serverProperties <- list(edition= tolower(sqlResult$Edition), engineEdition=as.integer(sqlResult$EngineEdition))
        productVersion <- as.integer(unlist(strsplit(sqlResult$ProductVersion, "\\.")))
        names(productVersion) <- c( "major", "minor", "build", "revision" )[1:length(productVersion)]
        serverProperties <- append(serverProperties, productVersion)
    }
    return (serverProperties)
}

#
# Returns list containing matrix with installed packages, warnings and errors
#
sqlEnumPackages <- function(connectionString, owner, scope, priority, fields, subarch)
{
    result <- list(packages = NULL, warnings = NULL, errors = NULL)

    scopeint <- parseScope(scope)

    pkgGetLibraryPath <- function(scopeint)
    {
        if (!all.equal(scopeint,as.integer(scopeint))){
            stop("pkgGetLibraryPathExtLib(): scope expected to be an integer", call. = FALSE)
        }

        if (scopeint == 0){
            extLibPath <- Sys.getenv("MRS_EXTLIB_SHARED_PATH")
        } else if (scopeint == 1){
            extLibPath <- Sys.getenv("MRS_EXTLIB_USER_PATH")
        } else {
            stop(paste0("pkgGetLibraryPathExtLib(): invalid scope value ", scopeint, ""), call. = FALSE)
        }

        extLibPath <- normalizePath(extLibPath, mustWork = FALSE)
        extLibPath <- gsub('\\\\', '/', extLibPath)

        return(extLibPath)
    }

    #
    # Returns PRIVATE, PUBLIC and SYSTEM library paths in a data frame in this order
    #
    sqlGetScopeLibraryPaths <- function(connectionString)
    {
        getScopeLibraryPaths <- function()
        {
            publicPath <- try(pkgGetLibraryPath(0), silent = TRUE)
            if (inherits(publicPath, "try-error"))
            {
                publicPath <- NA
            }

            privatePath <- try(pkgGetLibraryPath(1), silent = TRUE)
            if (inherits(privatePath, "try-error"))
            {
                privatePath <- NA
            }

            systemPath <- .Library

            scopes <- c("PRIVATE", "PUBLIC", "SYSTEM")

            return (data.frame(Scope = scopes, Path = c(privatePath, publicPath, systemPath), row.names = scopes, stringsAsFactors = FALSE))
        }

        libPaths <- sqlRemoteExecuteFun(connectionString, getScopeLibraryPaths, asuser = owner, includeFun = list(pkgGetLibraryPath = pkgGetLibraryPath))


        return(libPaths)
    }

    #
    # Appends installed packages for a specific scope & library path
    #
    addInstalledPackages <- function(connectionString, installedPackages = NULL, libScope, libPath, priority = NULL, fields = "Package", subarch = NULL)
    {
        result <- list(installedPackages = NULL, warnings = NULL, errors = NULL)

        #
        # Returns data frame will list of all packages and their 'isTopLevel' attribute for given owner and scope
        # If attribute 'isTopLevel' is not set for a package it will be -1
        #
        sqlQueryIsTopPackageExtLib <- function(connectionString, packagesNames, owner, scope)
        {
            scopeint <- parseScope(scope)

            result <- enumerateTopPackages(
                connectionString = connectionString,
                packages = packagesNames,
                owner = owner,
                scope = scopeint)

            if (is.null(result) || nrow(result)<1)
            {
                return(NULL)
            }
            else if (is.data.frame(result))
            {
                rownames(result) <- result$name
                return (result)
            }
        }

        # enumerate packages installed under sql server R library path
        packages <- NULL
        tryCatch({
            packages <- sqlRemoteExecuteFun(connectionString, utils::installed.packages, lib.loc = libPath, noCache = TRUE,
                                            priority = priority, fields = NULL, subarch = subarch,
                                            useRemoteFun = TRUE, asuser = owner)
        },
        error = function(err){
            stop(paste0("failed to enumerate installed packages on library path: ", err$message), call. = FALSE)
        }
       )

        if (!is.null(packages) && nrow(packages)>0)
        {
            packages <- cbind(packages, Attributes = rep(NA, nrow(packages)), Scope = rep(libScope, nrow(packages)))

            # get top package flag if attributes column will be present in final results and if we are in PUBLIC or PRIVATE scope
            if (nrow(packages) > 0 && (libScope == 'PUBLIC' || libScope == 'PRIVATE'))
            {
                filteredPackages <- processInstalledPackagesResult(packages, fields)
                if ('Attributes' %in% colnames(filteredPackages))
                {
                    packagesNames <- rownames(packages[packages[,'Scope'] == libScope,, drop = FALSE])

                    if (length(packagesNames) > 0)
                    {
                        isTopPackageDf<-sqlQueryIsTopPackageExtLib(connectionString, packagesNames, owner, libScope)

                        if (!is.null(isTopPackageDf))
                        {
                            for(pkg in packagesNames)
                            {
                                if (packages[pkg,'Scope'] == libScope)
                                {
                                    isTopPackage <- as.integer(isTopPackageDf[pkg,'IsTopPackage'])
                                    if (isTopPackage == IS_TOP_PACKAGE_MISSING){
                                        isTopPackage = 1
                                    }
                                    packages[pkg,'Attributes'] <- isTopPackage
                                }
                            }
                        }
                    }
                }
            }


            if (is.null(installedPackages))
            {
                installedPackages <- packages
            }
            else
            {
                installedPackages <- rbind(installedPackages, packages)
            }
        }

        result$installedPackages <- installedPackages

        return(result)
    }

    extLibPaths <- sqlGetScopeLibraryPaths(connectionString)

    installedPackages <- NULL
    for(i in 1:nrow(extLibPaths))
    {
        libPath <- extLibPaths[i, "Path"]

        if (!is.na(libPath))
        {
            libScope <- extLibPaths[i, "Scope"]

            ret <- NULL
            if (libScope == "PRIVATE")
            {
                if (scope == "PRIVATE")
                {
                    ret <- addInstalledPackages(connectionString, installedPackages, libScope, libPath, priority, fields, subarch)
                }
            }
            else
            {
                ret <- addInstalledPackages(connectionString, installedPackages, libScope, libPath, priority, fields, subarch)
            }
            if (!is.null(ret)){
                installedPackages <- ret$installedPackages
                result$warnings <- c(result$warnings,ret$warnings)
                result$errors <- c(result$errors,ret$errors)
            }
        }
    }

    installedPackages <- processInstalledPackagesResult(installedPackages, fields)

    result$packages <- installedPackages

    return(result)
}

getDependentPackagesToInstall <- function(pkgs, availablePackages, installedPackages, skipMissing = FALSE,
                                            verbose = getOption("verbose"))
{
    #
    # prune requested packages to exclude base packages
    #
    basePackages <- installedPackages[installedPackages[,"Priority"] %in% c("base", "recommended"), c("Package", "Priority"), drop = FALSE]$Package
    droppedPackages <- pkgs[pkgs %in% basePackages]

    if (length(droppedPackages) > 0)
    {
        warning(sprintf("Skipping base packages (%s)", paste(droppedPackages, collapse = ', ')), call. = FALSE)
    }

    pkgs <- pkgs[!(pkgs %in% droppedPackages)]

    if (length(pkgs) < 1)
    {
        return (NULL)
    }

    #
    # get dependency closure for all given packages
    # note: by default we obtain a package+dependencies from one CRAN which should have versions that work together without conflicts.
    #
    if (verbose)
    {
        write(sprintf("%s  Resolving package dependencies for (%s)...", pkgTime(), paste(pkgs, collapse = ', ')), stdout())
    }

    dependencies <- tools::package_dependencies(packages = pkgs, db = availablePackages, recursive = TRUE, verbose = FALSE)

    #
    # get combined dependency closure w/o base packages
    #
    dependencies <- unique(unlist(c(dependencies, names(dependencies)), recursive = FALSE, use.names = FALSE))
    dependencies <- dependencies[dependencies != "NA"]
    dependencies <- dependencies[!(dependencies %in% basePackages)]

    if (length(dependencies) < 1)
    {
        return (NULL)
    }

    #
    # are there any missing packages in dependency closure?
    #
    availablePackageNames <- rownames(availablePackages)
    missingPackages <- dependencies[!(dependencies %in% availablePackageNames)]

    if (length(missingPackages) > 0)
    {
        missingPackagesStr <- sprintf("Missing dependency packages (%s)", paste(missingPackages, collapse = ', '))

        if (!skipMissing)
        {
            stop(missingPackagesStr, call. = FALSE)
        }
        else
        {
            warning(missingPackagesStr, call. = FALSE)
        }
    }

    #
    # get the packages in order of dependency closure
    #
    dependencies <- unique(dependencies)
    pkgsToInstall <- availablePackages[match(dependencies, availablePackageNames),]
    pkgsToInstall <- pkgsToInstall[!is.na(pkgsToInstall$Package),]

    return (pkgsToInstall)
}

#
# Returns list with 2 data frames.
# First data frames containes pruned packages to install
# Second data frame contains pruned packages to mark as top-level
#
prunePackagesToInstallExtLib <- function(dependentPackages, topMostPackages, installedPackages, verbose = getOption("verbose"))
{
    prunedPackagesToInstall <- NULL
    prunedPackagesToTop <- NULL

    if (is.null(dependentPackages))
    {
        return(list(NULL, NULL))
    }

    for (pkgToInstallIndex in 1:nrow(dependentPackages))
    {
        pkgToInstall <- dependentPackages[pkgToInstallIndex,]

        # get available packages that match the name of the package we depend on
        availablePkgs <- installedPackages[match(pkgToInstall$Package, installedPackages$Package, nomatch = 0),, drop = FALSE]


        if (nrow(availablePkgs) == 0)
        {
            # no packages available, add packages we depend to the list of pruned packages to install
            prunedPackagesToInstall <- rbind(prunedPackagesToInstall, pkgToInstall)
        }
        else
        {
            # If a package A is installed that depends on B and B is already installed, 3 scenarios are possible:
            # (1) versions are the same -> OK
            # (2) installed version is newer -> OK
            # (3) installed version is older -> we print a warning to allow user to make proper decision
            for(scope in c("PRIVATE", "PUBLIC", "SYSTEM"))
            {
                availablePkg <- availablePkgs[ availablePkgs$Scope == scope,, drop = FALSE ]
                if (nrow(availablePkg) == 1){
                    if (utils::compareVersion(availablePkg$Version, pkgToInstall$Version) == -1){
                        #pkgToInstall is newer (later) than availablePkg
                        warning(sprintf("package is already installed but version is older than available in repos: package='%s', scope='%s', currently installed version='%s', new version=='%s'", pkgToInstall$Package, scope, availablePkg$Version, pkgToInstall$Version), call. = FALSE)
                    }
                    break
                }
            }

            # if the available package is being requested as a top-level package we check
            # if the top-leve attribute on the package is set to false we will have to update it to true
            if ('Attributes' %in% colnames(installedPackages)){
                if (pkgToInstall$Package %in% topMostPackages){ # package to install is requested as top-level
                    # if package is marked as depended we have to set it as top-level
                    pkgToTop <- availablePkgs[!is.na(availablePkgs[,'Attributes']) &
                                                  bitwAnd(as.integer(availablePkgs[,'Attributes']), getPackageTopMostAttributeFlag()) ==  0
                                              ,, drop = FALSE]
                    if (nrow(pkgToTop) > 0)
                    {
                        prunedPackagesToTop <- rbind(prunedPackagesToTop, pkgToTop)
                    }
                }
            }
        }
    }

    return (list(prunedPackagesToInstall, prunedPackagesToTop))
}

downloadDependentPackages <- function(pkgs, destdir, binaryPackages, sourcePackages,
                                        verbose = getOption("verbose"), pkgType = getOption("pkgType"))
{
    downloadedPkgs <- NULL
    numPkgs <- nrow(pkgs)

    for (pkgIndex in 1:numPkgs)
    {
        pkg = pkgs[pkgIndex,]

        if (verbose)
        {
            write(sprintf("%s  Downloading package [%d/%d] %s (%s)...", pkgTime(), pkgIndex, numPkgs, pkg$Package, pkg$Version), stdout())
        }

        #
        # try first binary package
        #
        downloadedPkg <- utils::download.packages(pkg$Package, destdir = destdir,
                                                  available = binaryPackages, type = pkgType, quiet = TRUE)

        if (length(downloadedPkg) < 1)
        {
            #
            # try source package if binary package isn't there
            #
            downloadedPkg <- utils::download.packages(pkg$Package, destdir = destdir,
                                                      available = sourcePackages, type = "source", quiet = TRUE)
        }

        if (length(downloadedPkg) < 1)
        {
            stop(sprintf("Failed to download package %s.", pkg$Package), call. = FALSE)
        }

        downloadedPkg[1,2] <- normalizePath(downloadedPkg[1,2], mustWork = FALSE)
        downloadedPkgs <- rbind(downloadedPkgs, downloadedPkg)
    }

    downloadedPkgs <- data.frame(downloadedPkgs, stringsAsFactors = FALSE)
    colnames(downloadedPkgs) <- c("Package", "File")
    rownames(downloadedPkgs) <- downloadedPkgs$Package

    return (downloadedPkgs)
}


#
# Installs packages using external library ddl support
#
sqlInstallPackagesExtLib <- function(connectionString,
                                        pkgs,
                                        skipMissing = FALSE, repos, verbose,
                                        scope = "private", owner = '',
                                        serverVersion = serverVersion)
{
    g_scriptFile <- local(g_scriptFile, install.env)
    #
    # check permissions
    #
    checkPermission <- function(connectionString, scope, owner, verbose)
    {
        sqlCheckPermission <- function(connectionString, scope, owner)
        {
            allowed <- FALSE

            haveOwner <- (nchar(owner) > 0)
            query <- ""

            if (haveOwner){
                query <- paste0("EXECUTE AS USER = '", owner , "';\n")
            }

            query <- paste0(query, "SELECT USER;")

            if (haveOwner) {
                query <- paste0(query, "\nREVERT;")
            }

            hodbc <- odbcDriverConnect(connectionString)
            checkOdbcHandle(hodbc, connectionString)
            on.exit(odbcClose(hodbc), add = TRUE)

            if(!is.null(g_scriptFile)) {
                cat(query, file=g_scriptFile, append=TRUE)
                cat("\n", file=g_scriptFile, append=TRUE)
            }
            sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)


            if (is.data.frame(sqlResult))
            {
                user <- sqlResult[1,1]

                if (user == '')
                {
                    allowed <- FALSE
                }
                else if (scope == "PRIVATE" && user == "dbo")
                {
                    # block dbo call to install into PRIVATE library path which is not supported by create external library
                    allowed <- FALSE
                }
                else
                {
                    allowed <- TRUE
                }
            }
            else
            {
                #cannot execute as the database principal because the principal "x" does not exist
                allowed <- FALSE
            }

            return (allowed)
        }

        if (verbose)
        {
            write(sprintf("%s  Verifying permissions to install packages on SQL server...", pkgTime()), stdout())
        }

        if (scope == "PUBLIC")
        {
            if (is.character(owner) && nchar(owner) >0)
            {
                stop(paste0("Invalid use of scope PUBLIC. Use scope 'PRIVATE' to install packages for owner '", owner ,"'\n"), call. = FALSE)
            }
        }
        else if (scope == "PRIVATE")
        {
            # fail dbo calls to install to private scope as dbo can only install to public
            scopeint <- parseScope(scope)
            allowed <- sqlCheckPermission(connectionString, scope, owner)

            if (!allowed)
            {
                stop(sprintf("Permission denied for installing packages on SQL server for current user: scope='%s', owner='%s'.", scope, owner), call. = FALSE)
            }
        }
    }

    attributePackages <- function(connectionString, packages, scopeint, owner, verbose)
    {
        packagesNames <- sapply(packages, function(pkg){pkg$name},USE.NAMES = FALSE)

        if (verbose)
        {
            write(sprintf("%s  Attributing packages on SQL server (%s)...", pkgTime(), paste(packagesNames, collapse = ', ')), stdout())
        }

        result <- sqlMakeTopLevel(connectionString = connectionString,
                                  packages = packagesNames,
                                  owner = owner,
                                  scope = as.integer(scopeint))

        if (result) {
            write(sprintf("Successfully attributed packages on SQL server (%s).",
                          paste(packagesNames, collapse = ', ')), stdout())
        }
    }

    # check scope and permission to write to scoped folder
    scope <- normalizeScope(scope)
    scopeint <- parseScope(scope)

    if(verbose){
        write(sprintf("%s  Starting package install on SQL server (%s)...", pkgTime(), connectionString), stdout())
    } else {
        write(sprintf("(package install may take a few minutes, set verbose=TRUE for progress report)"), stdout())
    }

    checkPermission(connectionString, scope, owner, verbose)

    topMostPackageFlag <- getPackageTopMostAttributeFlag()

    if (length(pkgs) > 0)
    {
        downloadDir <- tempfile("download")
        dir.create(downloadDir)
        on.exit(unlink(downloadDir, recursive = TRUE), add = TRUE)

        packages <- list()

        if (missing(repos) || length(repos) > 0)
        {
            #
            # get the contrib URLs
            # (when client R and server R have different versions
            #  use server R version to find matching packages in repos)
            #
            contribSource <- NULL
            contribWinBinary <- NULL

            getContribUrls <- function(serverIsWindows)
            {
                repos <- getOption("repos")

                contribSource <- utils::contrib.url(repos = repos, type = "source")
                contribWinBinary <- NULL
                if (serverIsWindows)
                    contribWinBinary <-utils::contrib.url(repos = repos, type = "win.binary")

                return (list(ContribSource = contribSource, ContribWinBinary = contribWinBinary))
            }

            if(missing(repos)){
                rversion <- getRversionContribFormat()
                if(rversion == serverVersion$rversion){
                    contribs <- getContribUrls(serverVersion$serverIsWindows)
                } else {
                    write(sprintf("R version installed on sql server (%s) is different from the R version on client (%s). Using sql server R version to find matching packages in repositories.",  serverVersion$rversion, rversion), stdout())
                    contribs <- sqlRemoteExecuteFun(connectionString, getContribUrls, serverVersion$serverIsWindows)
                }
                contribSource <- contribs$ContribSource
                contribWinBinary <- contribs$ContribWinBinary
            } else {
                # caller specified repo
                contribSource <- utils::contrib.url(repos = repos, type = "source")
                if(serverVersion$serverIsWindows)
                    contribWinBinary <- utils::contrib.url(repos = repos, type = "win.binary")
            }

            #
            # get the available package lists
            #
            sourcePackages <- utils::available.packages(contribSource, type = "source")
            row.names(sourcePackages) <- NULL


            binaryPackages <- if (serverVersion$serverIsWindows) utils::available.packages(contribWinBinary, type = "win.binary") else NULL
            row.names(binaryPackages) <- NULL
            pkgsUnison <-  data.frame(rbind(sourcePackages, binaryPackages), stringsAsFactors = FALSE)
            pkgsUnison <- pkgsUnison[!duplicated(pkgsUnison$Package),,drop=FALSE]
            row.names(pkgsUnison) <- pkgsUnison$Package

            #
            # check for missing packages
            #
            missingPkgs <- pkgs[!(pkgs %in% pkgsUnison$Package) ]

            if (length(missingPkgs) > 0)
            {
                stop(sprintf("Cannot find specified packages (%s) to install", paste(missingPkgs, collapse = ', ')), call. = FALSE)
            }

            #
            # get all installed packages
            #
            installedPackages <- sql_installed.packages(connectionString, fields = NULL, scope = scope, owner =  owner, scriptFile = g_scriptFile)
            installedPackages <- data.frame(installedPackages, row.names = NULL, stringsAsFactors = FALSE)

            #
            # get dependency closure of given packages
            #
            pkgsToDownload <- getDependentPackagesToInstall(pkgs = pkgs, availablePackages = pkgsUnison,
                                                            installedPackages = installedPackages,
                                                            skipMissing = skipMissing, verbose = verbose)

            #
            # prune dependencies for already installed packages
            #
            prunedPkgs <- prunePackagesToInstallExtLib(dependentPackages = pkgsToDownload,
                                                       topMostPackages = pkgs,
                                                       installedPackages = installedPackages, verbose = verbose)
            pkgsToDownload <- prunedPkgs[[1]]
            pkgsToAttribute <- prunedPkgs[[2]]


            if (length(pkgsToDownload) < 1 && length(pkgsToAttribute) < 1)
            {
                write(sprintf("Packages (%s) are already installed.", paste(pkgs, collapse = ', ')), stdout())

                return (invisible(NULL))
            }

            if (length(pkgsToDownload) > 0)
            {
                serverVersion <- checkVersion(connectionString)
                if (serverVersion$serverIsWindows)
                {
                    pkgType = "win.binary"
                }
                else
                {
                    pkgType = "source"
                }

                #
                # download all the packages in dependency closure
                #
                downloadPkgs <- downloadDependentPackages(pkgs = pkgsToDownload, destdir = downloadDir,
                                                          binaryPackages = binaryPackages, sourcePackages = sourcePackages,
                                                          verbose = verbose, pkgType = pkgType)
            }

            if (length(pkgsToDownload) > 0)
            {
                attributesVec<-apply(downloadPkgs, 1, function(x){
                    packageAttributes <- 0x0
                    if (x["Package"] %in% pkgs){
                        packageAttributes <- bitwOr(packageAttributes,topMostPackageFlag)
                    }
                    return (packageAttributes)
                }
               )

                downloadPkgs <- cbind(downloadPkgs, Attribute = attributesVec)
                sqlHelperInstallPackages(connectionString, downloadPkgs, owner, scope, verbose)

            }

            if (length(pkgsToAttribute) > 0)
            {
                for (packageIndex in 1:nrow(pkgsToAttribute))
                {
                    packageDescriptor <- list()
                    packageDescriptor$name <- pkgsToAttribute[packageIndex,"Package"]
                    packageAttributes <- 0x0
                    if (packageDescriptor$name %in% pkgs){
                        packageAttributes <- bitwOr(packageAttributes,topMostPackageFlag)
                    }
                    packageDescriptor$attributes <- packageAttributes


                    packages[[length(packages) + 1]] <- packageDescriptor
                }

                attributePackages(connectionString, packages, scopeint, owner, verbose)
            }

        }
        else
        {
            # caller set repos = NULL, packages are file paths
            pkgs <- normalizePath(pkgs, mustWork = FALSE)
            missingPkgs <- pkgs[!file.exists(pkgs)]

            if (length(missingPkgs) > 0)
            {
                stop(sprintf("%s packages are missing.", paste0(missingPkgs, collapse = ", ")), call. = FALSE)
            }

            packages <- data.frame(matrix(nrow = 0, ncol = 3), stringsAsFactors = FALSE)
            for( packageFile in pkgs){
                packages <- rbind(packages, data.frame(
                    Package = unlist(lapply(strsplit(basename(packageFile), '\\.|_'), '[[', 1), use.names =  F),
                    File = packageFile,
                    Attribute = topMostPackageFlag,
                    stringsAsFactors = FALSE))
            }

            sqlHelperInstallPackages(connectionString, packages, owner, scope, verbose)
        }

    }
}

#
# Calls CREATE EXTERNAL LIBRARY on a package
#
sqlCreateExternalLibrary <- function(hodbc, packageName, packageFile, user = "")
{
    g_scriptFile <- local(g_scriptFile, install.env)
    # read zip file into binary format
    fileConnection <- file(packageFile, 'rb')
    pkgBin <- readBin(con = fileConnection, what = raw(), n = file.size(packageFile))
    close(fileConnection)
    pkgContent = paste0("0x", paste0(pkgBin, collapse = ""));


    haveUser <- (user != '')

    query <- paste0("CREATE EXTERNAL LIBRARY [", packageName, "]")

    if (haveUser){
        query <- paste0(query, " AUTHORIZATION ", user)
    }

    query <- paste0(query, " FROM (CONTENT=", pkgContent ,") WITH (LANGUAGE = 'R');")

    if(!is.null(g_scriptFile)) {
        cat(query, file=g_scriptFile, append=TRUE)
        cat("\n", file=g_scriptFile, append=TRUE)
    }
    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.character(sqlResult) && length(sqlResult) == 0){
        return (TRUE)
    }

    # sqlResult contains character vector of error messages
    stop(paste(sqlResult, collapse = "\n"))
}

#
# Calls DROP EXTERNAL LIBRARY on a package
#
sqlDropExternalLibrary <- function(hodbc, packageName, user = "")
{
    g_scriptFile <- local(g_scriptFile, install.env)
    haveUser <- (user != '')

    query <- paste0("DROP EXTERNAL LIBRARY [", packageName, "]")

    if (haveUser){
        query <- paste0(query, " AUTHORIZATION ", user, ";")
    }

    if(!is.null(g_scriptFile)) {
        cat(query, file=g_scriptFile, append=TRUE)
        cat("\n", file=g_scriptFile, append=TRUE)
    }
    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.character(sqlResult) && length(sqlResult) == 0){
        return (TRUE)
    }

    # sqlResult contains character vector of error messages
    stop(paste(sqlResult, collapse = "\n"), call. = FALSE)
}

#
# Adds extendend property to package to store attributes (Top level package)
#
sqlAddExtendedProperty <- function(hodbc, packageName, attributes, user = "")
{
    g_scriptFile <- local(g_scriptFile, install.env)
    isTopLevel <- attributes & 0x1;

    haveUser <- (user != '')


    # use extended property to set top level packages
    if (haveUser){
        # if we have an user bind it to the query
        query <- paste0("EXEC sp_addextendedproperty @name = N'IsTopPackage', @value=", isTopLevel,", @level0type=N'USER', @level0name=",user,", @level1type = N'external library', @level1name =", packageName)
    } else {
        # if user is empty we use the current user
        query <- paste0("DECLARE @currentUser NVARCHAR(128); SELECT @currentUser = CURRENT_USER; EXEC sp_addextendedproperty @name = N'IsTopPackage', @value=", isTopLevel,", @level0type=N'USER', @level0name=@currentUser, @level1type = N'external library', @level1name =", packageName)
    }

    if(!is.null(g_scriptFile)) {
        cat(query, file=g_scriptFile, append=TRUE)
        cat("\n", file=g_scriptFile, append=TRUE)
    }
    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.character(sqlResult)){
        return (TRUE)
    }

    # error happened, vector of string contains error messages
    stop(paste(sqlResult, sep = "\n"))
}

sqlMakeTopLevel <- function(connectionString, packages, owner, scope)
{
    changeTo = 1
    haveUser <- (owner != '')

    if (haveUser) {
        user = "?"
        query = ""
    } else {
        user = "@currentUser"
        query = "DECLARE @currentUser NVARCHAR(128);
        SELECT @currentUser = CURRENT_USER;"
    }
    query = paste0(query, "EXEC sp_updateextendedproperty @name = N'IsTopPackage', @value=", changeTo,", @level0type=N'USER',
                   @level0name=", user, ", @level1type = N'external library', @level1name=?")

    packageList <- enumerateTopPackages(connectionString, packages, owner, scope)$name

    tryCatch({
        hodbc <- odbcDriverConnect(connectionString)
        checkOdbcHandle(hodbc, connectionString)

        for(pkg in intersect(packages,packageList)) {
            if (haveUser) {
                result <- sqlExecute(hodbc, query = query,
                                     owner, pkg,
                                     fetch = TRUE)
            } else {
                result <- sqlExecute(hodbc, query = query,
                                     pkg,
                                     fetch = TRUE)
            }
        }
    }, error = function(err) {
        stop(sprintf("Attribution of packages %s failed with error %s",
                     paste(packages, collapse = ', '), err$message), call. = FALSE)
    }, finally = {
        if (hodbc != -1){
            odbcClose(hodbc)
        }
    })
    return(TRUE)
}

#
# Returns data frame with packages names and associated external library id  |name|external_library_id|
#
sqlQueryExternalLibraryId <- function(hodbc, packagesNames, scopeint, queryUser)
{
    query <- paste0(
        " SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;", # Sets transactions isolation level to read uncommited for the current connections so we can read external library ids
        " DECLARE @currentUser NVARCHAR(128);",
        " DECLARE @principalId INT;"
    )

    query <- paste0(query, " SELECT @currentUser = ", queryUser, ";")

    query <- paste0(query,
                    " SELECT @principalId = USER_ID(@currentUser);",
                    " SELECT name, external_library_id",
                    " FROM sys.external_libraries AS elib",
                    " WHERE elib.name in (",
                    paste0("'", paste(packagesNames, collapse = "','"), "'"),
                    ")",
                    " AND elib.principal_id=@principalId",
                    " AND elib.language='R' AND elib.scope=", scopeint,
                    " ORDER BY elib.name ASC",
                    " ;"
    )

    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    if (is.data.frame(sqlResult))
    {
        rownames(sqlResult) <- sqlResult[,"name"]
    }

    return(sqlResult)
}

#
# Returns data frame with packages, error codes and error messages from sys.external_library_setup_errors
# for any packages that failed to install/uninstall
#
# |external_library_id|error_code|error_timestamp|error_message|name|
#
sqlQueryExternalLibrarySetupErrors <- function(hodbc, externalLibraryIds, queryUser)
{
    query <- paste0(
        " DECLARE @currentUser NVARCHAR(128);",
        " DECLARE @principalId INT;"
    )

    query <- paste0(query, " SELECT @currentUser = ", queryUser, ";")

    query <- paste0(query,
                    " SELECT @principalId = USER_ID(@currentUser);",
                    " IF OBJECT_ID(N'sys.external_library_setup_errors') IS NOT NULL (",
                    " SELECT external_library_id, error_code, error_timestamp, error_message",
                    " FROM sys.external_library_setup_errors",
                    " WHERE external_library_id in (",
                    paste(externalLibraryIds[, "external_library_id"], collapse = ","),
                    ")",
                    " AND db_id=DB_ID()",
                    " AND principal_id=@principalId",
                    " ) ELSE (SELECT 'OBJECT_NOT_FOUND' AS OBJECT_NOT_FOUND);"
    )

    sqlResult <- sqlExecute(hodbc, query = query, fetch = TRUE, errors = TRUE, stringsAsFactors = FALSE)

    if (is.data.frame(sqlResult))
    {
        if(colnames(sqlResult)[[1]]=="OBJECT_NOT_FOUND"){
            sqlResult <- NULL
        } else {
            sqlResult <- merge(sqlResult, externalLibraryIds)
            rownames(sqlResult) <- sqlResult[, "name"]
        }
    }
    else if(!is.null(sqlResult))
    {
        sqlResult <- NULL
    }

    return(sqlResult)
}

#
# Returns dataframe with columns |Package(name of package)|Found(TRUE or FALSE)|
# Reports on all packages for the current scope (either PRIVATE or PUBLIC library path)
#
findPackages <- function(packages, scopeint)
{
    success <- TRUE
    resultdf <-data.frame(Package = NA, Found = NA, stringsAsFactors = FALSE)

    if (is.null(packages)) {
        stop('ERROR: input package list is empty')
        success <- FALSE
    }

    lib <-NULL
    if (scopeint == 0) {
        lib <-Sys.getenv('MRS_EXTLIB_SHARED_PATH')
    } else if (scopeint == 1) {
        lib <-Sys.getenv('MRS_EXTLIB_USER_PATH')
    } else {
        stop(paste0('ERROR: invalid scope=', scopeint))
        success <- FALSE
    }

    if (success)
    {
        resultdf <- data.frame(Package = packages, Found = rep(FALSE, length(packages)), row.names = packages, stringsAsFactors = FALSE)
        packagesFound <- find.package(packages, lib.loc = lib, quiet = TRUE)
        packagesNames <- unlist(lapply(packagesFound, basename))

        if (!is.null(packagesNames)){
            resultdf[packagesNames, 'Found'] <-TRUE
        }
    }

    return (resultdf)
}

#
# Syncs packages to the library path by calling sp_execute_external_script
# checks if packages are installed on library path
# The library path is determined by the scope and the user
#
# Returns vector of successfully installed packages
#
sqlSyncAndCheckInstalledPackages <- function(hodbc, packages, user = "", queryUser, scope = "PRIVATE")
{
    scopeint <- parseScope(scope)

    externalLibraryIds <- sqlQueryExternalLibraryId(hodbc, packages, scopeint, queryUser)

    # sp_execute_external_script will first install packages to the library path
    # and the run R function to check if packages installed
    checkdf <- sqlRemoteExecuteFun(hodbc, findPackages, packages, scopeint, asuser = user)

    setupFailures <- sqlQueryExternalLibrarySetupErrors(hodbc, externalLibraryIds, queryUser)

    # issue specific errors for packages that failed to install to the library path
    if((!is.null(setupFailures)) && (nrow(setupFailures) >0)){
        errors <- mapply(
            function(packageName, errorCode, errorMessage){
                sprintf("failed to install package (%s) to library path: user='%s', scope='%s', error code='%s', error message='%s'", packageName, user, scope, as.hexmode(errorCode), errorMessage)
            },
            setupFailures[,"name"], setupFailures[,"error_code"], setupFailures[,"error_message"]
        )
        stop(paste(errors, collapse = " ; "), call. = FALSE)
    }

    # issue generic errors for packages not found in library path
    failedPackages <- unlist(mapply(
        function(packageName,found){
            if (found == FALSE){
                return (packageName)
            }
            return (NULL)
        },
        checkdf[,"Package"], checkdf[,"Found"],
        SIMPLIFY=TRUE,
        USE.NAMES=FALSE
    ))
    if(length(failedPackages) >0){
        stop(sprintf("failed to install packages (%s) to library path: user='%s', scope='%s'", paste(failedPackages, collapse = ", "), user, scope), call. = FALSE)
    }

    return(packages)
}

sqlHelperInstallPackages <- function(connectionString, packages, owner = "", scope = "PRIVATE", verbose)
{
    user <- "" # user argument for Create External Library
    queryUser <- "CURRENT_USER" # user argument for select to discover external_library_id

    scopeint <- parseScope(scope)

    if (scopeint == 0 && owner == '')
    {
        # if scope is public the user has to be either dbo or member of db_owner
        # if current user is already dbo we just proceed, else if user
        # is member of db_owner (e.g. RevoTester) we run as 'dbo' to
        # force it to install into the public folder instead of the private.
        currentUser <- sqlSelectUser(connectionString);
        if (currentUser == "dbo")
        {
            user <- ""
            queryUser = "CURRENT_USER"
        }
        else
        {
            user <- "dbo"
            queryUser = "'dbo'"
        }
    }
    else
    {
        user <- owner
        if (nchar(owner) >0)
        {
            queryUser <- paste0("'", owner, "'")
        }
    }

    hodbc <- -1
    haveTransaction <- FALSE
    packagesSuccess <- c()
    tryCatch({
        hodbc <- odbcDriverConnect(connectionString)
        checkOdbcHandle(hodbc, connectionString)
        checkResult( odbcSetAutoCommit(hodbc, autoCommit = FALSE), 0, "failed to create transaction")
        haveTransaction <- TRUE

        numPkgs <- nrow(packages)
        for (packageIndex in 1:numPkgs)
        {
            packageName <- packages[packageIndex,"Package"]
            filelocation <- packages[packageIndex, "File"]
            attribute <- packages[packageIndex, "Attribute"]

            if (verbose)
            {
                write(sprintf("%s  Copying package to Sql server [%d/%d] %s...", pkgTime(), packageIndex, numPkgs, packageName), stdout())
            }
            sqlCreateExternalLibrary(hodbc, packageName, filelocation, user)
            sqlAddExtendedProperty(hodbc, packageName, attribute, user)
        }

        if (verbose)
        {
            write(sprintf("%s  Installing packages to library path, this may take some time...", pkgTime()), stdout())
        }
        packagesSuccess <- sqlSyncAndCheckInstalledPackages(hodbc, packages[,"Package"], user, queryUser, scope);
        odbcEndTran(hodbc, commit = TRUE)
    }
    , error = function(err) {
        stop( sprintf("Installation of packages %s failed with error %s", paste(packages[,"Package"], collapse = ', '), err$message), call. = FALSE)
    }
    , finally = {
        if(haveTransaction){
            # rollback / close open transactions otherwise odbcClose() will fail
            odbcEndTran(hodbc, commit = FALSE)
        }
        if(hodbc != -1){
            odbcClose(hodbc)
        }
    }
    )

    if(length(packagesSuccess) > 0){
        if(verbose){
            write(sprintf("%s  Successfully installed packages on SQL server (%s).", pkgTime(), paste(packagesSuccess, collapse = ', ')), stdout())
        } else {
            write(sprintf("Successfully installed packages on SQL server (%s).", paste(packagesSuccess, collapse = ', ')), stdout())
        }
    }
}


sqlHelperRemovePackages <- function(connectionString, pkgs, pkgsToDrop, pkgsToReport, scope, owner, verbose)
{
    user <- "" # user argument for Drop External Library
    queryUser <- "CURRENT_USER" # user argument for select to discover external_library_id

    scopeint <- parseScope(scope)

    if (scopeint == 0 && owner == '')
    {
        # if scope is public the user has to be either dbo or member of db_owner
        # if current user is already dbo we just proceed, else if user
        # is member of db_owner (e.g. RevoTester) we run as 'dbo' to
        # force it to install into the public folder instead of the private.
        currentUser <- sqlSelectUser(connectionString);
        if (currentUser == "dbo")
        {
            user <- ""
            queryUser = "CURRENT_USER"
        }
        else
        {
            user <- "dbo"
            queryUser = "'dbo'"
        }
    }
    else
    {
        user <- owner
        if (nchar(owner) >0)
        {
            queryUser <- paste0("'", owner, "'")
        }
    }

    hodbc <- -1
    haveTransaction <- FALSE
    pkgsSuccess <- c()
    tryCatch({
        hodbc <- odbcDriverConnect(connectionString)
        checkOdbcHandle(hodbc, connectionString)

        odbcSetAutoCommit(hodbc, autoCommit = FALSE)
        checkResult( odbcSetAutoCommit(hodbc, autoCommit = FALSE), 0, "failed to create transaction")
        haveTransaction <- TRUE

        # first drop potentially bad packages that fails to install during SPEES
        # then uninstall fully installed packages that will combine DROP + SPEES
        if (length(pkgsToDrop) > 0){
            lapply(pkgsToDrop, sqlDropExternalLibrary, hodbc = hodbc, user=user )
            pkgsSuccess <- c(pkgsSuccess, pkgsToDrop)
        }

        if (length(pkgs) > 0){
            # get the external library ids of all packages to be removed so we can cross-reference
            # with the view sys.external_library_setup_errors for errors reported
            # by the external library uninstaller
            externalLibraryIds <- sqlQueryExternalLibraryId(hodbc, pkgs, scopeint, queryUser)
            lapply(pkgs, sqlDropExternalLibrary, hodbc = hodbc, user=user)
            pkgsSuccess <- c(pkgsSuccess, sqlSyncRemovePackages(hodbc, c(pkgs,pkgsToReport), externalLibraryIds, scope, user, queryUser, verbose))
        } else if(length(pkgsToReport) > 0){
            pkgsSuccess <- c(pkgsSuccess, sqlSyncRemovePackages(hodbc, pkgsToReport, externalLibraryIds = NULL, scope, user, queryUser = NULL, verbose = verbose))
        }

        odbcEndTran(hodbc, commit = TRUE)
    }
    , error = function(err) {
        stop(sprintf("Removal of packages %s failed with error %s", paste(c(pkgs, pkgsToDrop, pkgsToReport), collapse = ', '), err$message), call. = FALSE)
    }, finally = {
        if(haveTransaction){
            # rollback / close open transactions otherwise odbcClose() will fail
            odbcEndTran(hodbc, commit = FALSE)
        }
        if(hodbc != -1){
            odbcClose(hodbc)
        }
    })

    if(length(pkgsSuccess) > 0){
        if(verbose){
            write(sprintf("%s  Successfully removed packages from SQL server (%s).", pkgTime(), paste(pkgsSuccess, collapse = ', ')), stdout())
        } else {
            write(sprintf("Successfully removed packages from SQL server (%s).", paste(pkgsSuccess, collapse = ', ')), stdout())
        }
    }
}

#
# Calls sp_execute_external packages to remove packages from library path
# that we previously dropped
#
# Checks if packages were successfully removed and reports any errors found
#
# Returns vector of successfully removed packages
#
sqlSyncRemovePackages <- function(hodbc, pkgs, externalLibraryIds, scope, user, queryUser, verbose)
{
    if(verbose){
        write(sprintf("%s  Removing packages from library path, this may take some time...", pkgTime()), stdout())
    }
    scopeint <- parseScope(scope)

    checkdf <- sqlRemoteExecuteFun(hodbc, findPackages, pkgs, scopeint, asuser = user)

    if(!(is.null(externalLibraryIds) || is.null(queryUser)))
    {
        setupFailures <- sqlQueryExternalLibrarySetupErrors(hodbc, externalLibraryIds, queryUser)

        # issue specific errors for packages that failed to be removed from  the library path
        if((!is.null(setupFailures)) && (nrow(setupFailures) >0)){
            errors <- mapply(
                function(packageName, errorCode, errorMessage){
                    sprintf("failed to remove package (%s) from library path: user='%s', scope='%s', error code='%s', error message='%s'", packageName, user, scope, as.hexmode(errorCode), errorMessage)
                },
                setupFailures[,"name"], setupFailures[,"error_code"], setupFailures[,"error_message"]
            )
            stop(paste(errors, collapse = " ; "), call. = FALSE)
        }
    }

    # issue generic errors for packages that are still present in the library path
    failedPackages <- unlist(mapply(
        function(packageName,found){
            if (found == TRUE){
                return (packageName)
            }
            return (NULL)
        },
        checkdf[,"Package"], checkdf[,"Found"],
        SIMPLIFY=TRUE,
        USE.NAMES=FALSE
    ))

    if(length(failedPackages) >0){
        stop(sprintf("failed to remove packages (%s) from library path: user='%s', scope='%s'", paste(failedPackages, collapse = ", "), user, scope), call. = FALSE)
    }

    return(pkgs)
}

#
# Returns data frame will list of packages found in sys.external_libraries
# columns in data frame are |Package|Found (TRUE or FALSE)|
# All submitted packages will be listed.
# If a package was  found in the database, find value will be TRUE otherwise FALSE
#
sqlEnumTable <- function(connectionString, packagesNames, owner, scopeint)
{
    g_scriptFile <- local(g_scriptFile, install.env)
    queryUser <- "CURRENT_USER"

    if (scopeint == 0) # public
    {
        currentUser <- sqlSelectUser(connectionString);
        if (currentUser == "dbo")
        {
            queryUser = "CURRENT_USER"
        }
        else
        {
            queryUser = "'dbo'"
        }
    }
    else if (nchar(owner) >0)
    {
        queryUser <- paste0("'", owner, "'")
    }

    query <- paste0(
        " DECLARE @currentUser NVARCHAR(128);",
        " DECLARE @principalId INT;"
   )

    query <- paste0(query, " SELECT @currentUser = ", queryUser, ";")

    query <- paste0(query,
                     " SELECT @principalId = USER_ID(@currentUser);",
                     " SELECT elib.name",
                     " FROM sys.external_libraries AS elib",
                     " WHERE elib.name in (",
                     paste0("'", paste(packagesNames, collapse = "','"), "'"),
                     ")",
                     " AND elib.principal_id=@principalId",
                     " AND elib.language='R' AND elib.scope=", scopeint,
                     " ORDER BY elib.name ASC",
                     " ;"
   )

    hodbc <- odbcDriverConnect(connectionString)
    checkOdbcHandle(hodbc, connectionString)
    on.exit(odbcClose(hodbc), add = TRUE)

    if(!is.null(g_scriptFile)) {
        cat(query, file=g_scriptFile, append=TRUE)
        cat("\n", file=g_scriptFile, append=TRUE)
    }
    sqlResult <- sqlQuery(hodbc, query, stringsAsFactors = FALSE)

    resultdf <- data.frame(Package = packagesNames, Found = rep(FALSE, length(packagesNames)), row.names = packagesNames, stringsAsFactors = FALSE)

    if (is.data.frame(sqlResult))
    {
        resultdf[sqlResult[,"name"],"Found"] <- TRUE
    }

    return(resultdf)
}

getDependentPackagesToUninstall <- function(pkgs, installedPackages, dependencies = TRUE, checkReferences = TRUE, verbose = getOption("verbose"))
{
    excludeTopMostPackagesDependencies <- function(pkgsToRemove, dependencies, db, basePackages, verbose)
    {
        # This function remove, from the given packages dependency lists, all the packages which are top most (and their dependencies) which are not explicitly
        # stated to be removed

        prunedDependencies <- dependencies

        #If we have the topmost package information, remove, from the dependencies, packages which are marked as topmost
        if ('Attributes' %in% colnames(db)){

            # Find all the packegs , in the installed packages database, which are explicitly marked as top most
            topMostInstalledPackages <- db[!is.na(db[,'Attributes']) &
                                               bitwAnd(as.integer(db[,'Attributes']), getPackageTopMostAttributeFlag()) ==  1
                                           ,, drop = FALSE]

            topMostDependencies <- unique(unlist(dependencies, recursive = TRUE, use.names = FALSE))
            topMostDependencies <- topMostDependencies[topMostDependencies %in% topMostInstalledPackages[,"Package"]]

            if (length(topMostDependencies) != 0){
                # Exclude, from the top most dependencies the packages which we specifically asked to remove
                topMostDependencies <- topMostDependencies[!(topMostDependencies %in% pkgsToRemove)]
            }

            if (length(topMostDependencies) != 0){
                # Get the top most packages dependencies to ensure they can still work

                topMostDependencies <- unique(c(unlist(tools::package_dependencies(packages = topMostDependencies,
                                                                                   db = db, recursive = TRUE,
                                                                                   verbose = FALSE), recursive = TRUE, use.names = FALSE),
                                                topMostDependencies))

                # Remove the dependencies which are base classes to allow the correct code to use these
                topMostDependencies <- topMostDependencies[!topMostDependencies %in% basePackages]
            }

            if (length(topMostDependencies) != 0){
                skippedDependencies <- character(0)
                prunedDependencies <- lapply(X = dependencies,
                                             FUN = function(dependency){
                                                 skippedDependencies <<- c(skippedDependencies, dependency[dependency %in% topMostDependencies])
                                                 dependency[!dependency %in% topMostDependencies]
                                             })

                if (verbose && length(skippedDependencies) > 0){
                    write(sprintf("%s  skipping following top level dependent packages (%s)...", pkgTime(), paste(unique(skippedDependencies), collapse = ', ')), stdout())
                }
            }
        }

        prunedDependencies
    }

    #
    # prune requested packages to exclude base packages
    #
    basePackages <- installedPackages[installedPackages[,"Priority"] %in% c("base", "recommended"), c("Package", "Priority"), drop = FALSE]$Package

    droppedPackages <- pkgs[pkgs %in% basePackages]

    if (length(droppedPackages) > 0)
    {
        warning(sprintf("Skipping base packages (%s)", paste(droppedPackages, collapse = ', ')), call. = FALSE)
    }

    pkgs <- pkgs[!(pkgs %in% droppedPackages)]

    if (length(pkgs) < 1)
    {
        return (NULL)
    }

    if (dependencies == FALSE)
    {
        dependencies = pkgs
    }
    else
    {
        #
        # get dependency closure for all given packages
        #
        if (verbose)
        {
            write(sprintf("%s  Resolving package dependencies for (%s)...", pkgTime(), paste(pkgs, collapse = ', ')), stdout())
        }

        dependencies <- tools::package_dependencies(packages = pkgs, db = installedPackages, recursive = TRUE, verbose = FALSE)

        # Exclude, from the package dependencies, all the packages which are marked as top most and their dependencies
        dependencies <- excludeTopMostPackagesDependencies(pkgsToRemove = pkgs,
                                                           dependencies = dependencies,
                                                           db = installedPackages,
                                                           basePackages = basePackages,
                                                           verbose = verbose)

        dependencies <- c(dependencies, pkgs)

        #
        # get combined dependency closure w/o base packages
        #
        dependencies <- unique(unlist(c(dependencies, names(dependencies)), recursive = TRUE, use.names = FALSE))
        dependencies <- dependencies[dependencies != "NA" & dependencies != ""]
        dependencies <- dependencies[!(dependencies %in% basePackages)]

        if (length(dependencies) < 1)
        {
            return (NULL)
        }
    }

    if (checkReferences == TRUE)
    {
        #
        # get reverse dependency closure for all given packages
        #
        if (verbose)
        {
            write(sprintf("%s  Resolving package reverse dependencies for (%s)...", pkgTime(), paste(pkgs, collapse = ', ')), stdout())
        }

        pkgsToSkip <- list()

        for (dependency in dependencies)
        {
            rdependencies <- tools::package_dependencies(packages = dependency, db = installedPackages, reverse = TRUE, recursive = TRUE, verbose = FALSE)
            rdependencies <- unique(unlist(c(rdependencies, names(rdependencies)), recursive = TRUE, use.names = FALSE))
            rdependencies <- rdependencies[rdependencies != "NA"]
            rdependencies <- rdependencies[rdependencies != ""]
            rdependencies <- rdependencies[!(rdependencies %in% dependencies)]

            if (length(rdependencies) > 0)
            {
                if (dependency %in% pkgs)
                {
                    skipMessage <- sprintf("skipping package (%s) being used by packages (%s)...",
                                           dependency, paste(rdependencies, collapse = ', '))
                    warning(skipMessage, call. = FALSE)
                }
                else
                {
                    skipMessage <- sprintf("skipping dependent package (%s) being used by packages (%s)...",
                                           dependency, paste(rdependencies, collapse = ', '))
                    write(skipMessage, stdout())
                }

                pkgsToSkip <- c(pkgsToSkip, dependency)
            }
        }

        pkgsToSkip <- unique(unlist(pkgsToSkip, recursive = TRUE, use.names = FALSE))

        #
        # remove packages which are being referenced by other packages
        #
        dependencies <- dependencies[!(dependencies %in% pkgsToSkip)]

        if (length(dependencies) < 1)
        {
            return (NULL)
        }
    }

    #
    # get the packages in order of dependency closure
    #
    dependencies <- unique(dependencies)
    pkgsToRemove <- installedPackages[match(dependencies, installedPackages$Package),, drop = FALSE]
    pkgsToRemove <- pkgsToRemove[!is.na(pkgsToRemove$Package),]

    return (pkgsToRemove)
}

#
# Returns dataframe |name (package name)|IsTopPackage (-1,0,1)|
#
enumerateTopPackages <- function(connectionString, packages, owner, scope)
{
    haveUser <- (owner != '')

    query <- "DECLARE @principalId INT;
    DECLARE @currentUser NVARCHAR(128);"

    query <- paste0( query, paste(sapply( seq(1,length(packages)), function(i){paste0("DECLARE @pkg", toString(i), " NVARCHAR(MAX);")} ), collapse=" "))

    query = paste0( query, "SELECT @currentUser = ")

    if (haveUser) {
        query<-paste0(query, "?;")
        data  <- data.frame(name = owner, stringsAsFactors = FALSE)
    } else {
        query = paste0(query, "CURRENT_USER;")
        data  <- data.frame(matrix(nrow=1, ncol=0), stringsAsFactors = FALSE)
    }

    for(pkg in packages)
    {
        data <- cbind(data, pkg, stringsAsFactors = FALSE)
    }
    data <- cbind(data, scope = scope, stringsAsFactors = FALSE)


    query <- paste0( query, paste(sapply( seq(1,length(packages)), function(i){paste0("SELECT @pkg", toString(i), " = ?;")} ), collapse=" "))
    pkgcsv <- paste(sapply( seq(1,length(packages)), function(i){paste0("@pkg", toString(i))} ), collapse=",")

    query = paste0(query , sprintf("
                                   SELECT @principalId = USER_ID(@currentUser);
                                   WITH eprop
                                   AS (
                                   SELECT piv.major_id, CAST([IsTopPackage] as bit) AS IsTopPackage FROM sys.extended_properties
                                   PIVOT (min(value) FOR name IN ([IsTopPackage])) AS piv
                                   WHERE class_desc = 'EXTERNAL_LIBRARY'
                                  )
                                   SELECT elib.name, eprop.IsTopPackage
                                   FROM sys.external_libraries AS elib
                                   INNER JOIN eprop
                                   ON eprop.major_id = elib.external_library_id AND elib.name in (%s)
                                   AND elib.principal_id=@principalId
                                   AND elib.language='R' AND elib.scope=?
                                   ORDER BY elib.name ASC
                                   ;", pkgcsv))

    tryCatch({
        hodbc <- odbcDriverConnect(connectionString)
        checkOdbcHandle(hodbc, connectionString)

        result <- sqlExecute(hodbc, query = query,
                             data = data,
                             fetch = TRUE)

        missingPkgs <- packages[!(packages %in% result[,"name"])]
        result <- rbind(result, data.frame(name = missingPkgs, IsTopPackage =  rep(IS_TOP_PACKAGE_MISSING, length(missingPkgs)), stringsAsFactors = FALSE))
    }, error = function(err) {
        stop(sprintf("Failed to enumerate package attributes: pkgs=(%s), error='%s'",
                     paste(packages, collapse = ', '), err$message), call. = FALSE)
    }, finally = {
        if (hodbc != -1){
            odbcClose(hodbc)
        }
    })
    return(result)
}
