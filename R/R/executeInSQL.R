# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.


#'
#'Execute a function in SQL
#'
#'@param driver The driver to use for the connection - defaults to SQL Server
#'@param server The server to connect to - defaults to localhost
#'@param database The database to connect to - defaults to master
#'@param uid The user id for the connection. If uid is NULL, default to Trusted Connection
#'@param pwd The password for the connection. If uid is not NULL, pwd is required
#'
#'@return A fully formed connection string
#'
#'
#'@examples
#'\dontrun{
#'
#' connectionInfo()
#' [1] "Driver={SQL Server};Server=localhost;Database=master;Trusted_Connection=Yes;"
#'
#' connectionInfo(server="ServerName", database="AirlineTestDB", uid="username", pwd="pass")
#' [1] "Driver={SQL Server};Server=ServerName;Database=AirlineTestDB;uid=username;pwd=pass;"
#' }
#'
#'
#'@export
connectionInfo <- function(driver = "SQL Server", server = "localhost", database = "master",
                             uid = NULL, pwd = NULL)
{
    authorization <- "Trusted_Connection=Yes"

    if (!is.null(uid))
    {
        if (is.null(pwd))
        {
            stop("Need a password if using uid")
        }
        else
        {
            authorization = sprintf("uid=%s;pwd={%s}",uid,pwd)
        }
    }

    connection <- sprintf("Driver=%s;Server=%s;Database=%s;%s;", driver, server, database, authorization)
    connection
}

#'
#'Execute a function in SQL
#'
#'@param connectionString character string. The connectionString to the database
#'@param func closure. The function to execute
#'@param ... A named list of arguments to pass into the function
#'@param inputDataQuery character string. A string to query the database.
#' The result of the query will be put into a data frame into the first argument in the function
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'@param languageName string. Use a language name other than the default R, if using an EXTERNAL LANGUAGE.
#'
#'@return The returned value from the function
#'
#'@seealso
#'\code{\link{executeScriptInSQL}} to execute a script file instead of a function in SQL
#'
#'
#'@examples
#'\dontrun{
#' connection <- connectionInfo(database = "AirlineTestDB")
#'
#' foo <- function(in_df, arg)
#' {
#'     list(data = in_df, value = arg)
#' }
#'
#' executeFunctionInSQL(connection, foo, arg = 12345,
#'                      inputDataQuery = "SELECT top 1 * from airline5000")
#'}
#'
#'@import odbc
#'@export
executeFunctionInSQL <- function(connectionString, func, ..., inputDataQuery = "", getScript = FALSE, languageName = "R")
{
    inputDataName <- "InputDataSet"
    listArgs <- list(...)

    if (inputDataQuery != "")
    {
        funcArgs <- methods::formalArgs(func)

        if (length(funcArgs) < 1)
        {
            stop("To use the inputDataQuery variable, the function must have at least one input argument")
        }
        else
        {
            inputDataName <- funcArgs[[1]]
        }
    }

    binArgs <- serialize(listArgs, NULL)

    spees <- speesBuilderFromFunction(func = func,
                                      inputDataQuery = inputDataQuery,
                                      inputDataName = inputDataName,
                                      binArgs = binArgs,
                                      languageName = languageName)

    if (getScript)
    {
        return(spees)
    }
    else
    {
        resVal <- execute(connectionString, script = spees)
        return(resVal[[1]])
    }
}

#'
#'Execute a script in SQL
#'
#'@param connectionString character string. The connectionString to the database
#'@param script character string. The path to the script to execute in SQL
#'@param inputDataQuery character string. A string to query the database.
#' The result of the query will be put into a data frame into the variable "InputDataSet" in the environment
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'@param languageName string. Use a language name other than the default R, if using an EXTERNAL LANGUAGE.
#'
#'@return The returned value from the last line of the script
#'
#'@seealso
#'\code{\link{executeFunctionInSQL}} to execute a user function instead of a script in SQL
#'
#'@export
executeScriptInSQL <- function(connectionString, script, inputDataQuery = "", getScript = FALSE, languageName = "R")
{

    if (file.exists(script))
    {
        print(paste0("Script path exists, using file ", script))
    }
    else
    {
        stop("Script path doesn't exist")
    }

    text <- paste(readLines(script), collapse="\n")

    func <- function(InputDataSet, script)
    {
        eval(parse(text = script))
    }

    executeFunctionInSQL(connectionString = connectionString,
                         func = func,
                         script = text,
                         inputDataQuery = inputDataQuery,
                         getScript = getScript,
                         languageName = languageName)
}


#'
#'Execute a script in SQL
#'
#'@param connectionString character string. The connectionString to the database
#'@param sqlQuery character string. The query to execute
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'@param languageName string. Use a language name other than the default R, if using an EXTERNAL LANGUAGE.
#'
#'@return The data frame returned by the query to the database
#'
#'
#'@examples
#'\dontrun{
#' connection <- connectionInfo(database="AirlineTestDB")
#' executeSQLQuery(connection, sqlQuery="SELECT top 1 * from airline5000")
#'}
#'
#'
#'@export
executeSQLQuery <- function(connectionString, sqlQuery, getScript = FALSE, languageName = "R")
{
    #We use the serialize method here instead of OutputDataSet <- InputDataSet to preserve column names

    script <- " serializedResult <- as.character(serialize(list(result = InputDataSet), NULL))
                OutputDataSet <- data.frame(returnVal=serializedResult, stringsAsFactors=FALSE)
                list(result = InputDataSet)
              "
    spees <- speesBuilder(script = script,
                          inputDataQuery = sqlQuery,
                          languageName = languageName,
                          withResults = TRUE)

    if (getScript)
    {
        return(spees)
    }
    else
    {
        execute(connectionString, spees)$result
    }
}


#
# Use odbc and connection string to connect to a server
# @param connectionString character string. The connection to the database
#
connectToServer <- function(connectionString)
{
    dbConnect(odbc(), .connection_string = connectionString)
}

#
# Execute and process a script
#
# @param connection character string or S4 connection object, to connect to the database
# @param script character string. The script to execute
#
execute <- function(connection, script, ...)
{
    queryResult <- NULL

    # Check if the connection is a connection string or an odbc connection object (S4 object)
    #
    if (class(connection) == "character")
    {
        if (nchar(connection) < 1)
        {
            stop(paste0("Invalid connection string: ", connection), call. = FALSE)
        }
    }
    else if (typeof(connection) != "S4")
    {
        stop("Invalid connection string has to be a character string or odbc handle", call. = FALSE)
    }

    tryCatch(
    {
        # If we have a connection string, connect, then disconnect on exit.
        # If we have an actual connection object, use it but don't disconnect on exit.
        #
        if (class(connection) == "character")
        {
            hodbc <- connectToServer(connection)
            on.exit(dbDisconnect(hodbc), add = TRUE)
        }
        else
        {
            hodbc <- connection
        }

        queryResult <- dbSendQuery(hodbc, script)

        # Bind parameterized queries
        #
        if(length(list(...)) != 0)
        {
            dbBind(queryResult, ...)
        }

        res <- dbFetch(queryResult)

        binVal <- res$returnVal
    },
    error = function(e)
    {
        stop(paste0("Error in SQL Execution: ", e, "\n"))
    },
    finally =
    {
        if (!is.null(queryResult))
        {
            dbClearResult(queryResult)
        }
    })

    binVal <- res$returnVal

    if (!is.null(binVal))
    {
        resVal <- unserialize(unlist(lapply(lapply(as.character(binVal),as.hexmode), as.raw)))
        len <- length(resVal)

        # Each piece of the returned value is a different part of the output
        # 1. The result of the function
        # 2. The output of the function (e.g. from print())
        # 3. The warnings of the function
        # 4. The errors of the function
        # We raise warnings and errors, print any output, and return the actual function results to the user
        #
        if (len > 1)
        {
            output <- resVal[[2]]
            for (o in output)
            {
                cat(paste0(o,"\n"))
            }
        }

        if (len > 2)
        {
            warnings <- resVal[[3]]
            for (w in warnings)
            {
                warning(w)
            }
        }

        if (len > 3)
        {
            errors <- resVal[[4]]
            for (e in errors)
            {
                stop(paste0("Error in script: ", e))
            }
        }

        res <- resVal
    }

    return(res)
}


#
# Build an R sp_execute_external_script
#
# @param script The script to execute
# @param inputDataQuery The query on the database
# @param withResults Whether to have a result set, outside of the OutputDataSet
#
speesBuilder <- function(script, inputDataQuery, languageName, withResults = FALSE)
{
    resultSet <- if (withResults) "with result sets((returnVal varchar(MAX)))" else ""

    sprintf("exec sp_execute_external_script
            @language = N'%s',
            @script = N'
            %s
            ',
            @input_data_1 = N'%s'
            %s
            ", languageName, script, inputDataQuery, resultSet)
}

#
# Build a spees call from a function
#
# @param func The function to make into a spees
# @param inputDataQuery The input data query to the database
# @param inputDataName The name of the variable to put the data frame from the query into in the script
# @param binArgs The (binary) version of all arguments passed into the function
#
# @return The spees script to execute
# The spees script will return a data frame with the results, serialized
#
speesBuilderFromFunction <- function(func, inputDataQuery, inputDataName, binArgs, languageName)
{
    funcName <- deparse(substitute(func))
    funcBody <- gsub('"', '\"', paste0(deparse(func), collapse = "\n"))

    speesBody <- sprintf("
                         %s <- %s


                         oldWarn <- options(\"warn\")$warn
                         options(warn=1)

                         output <- NULL
                         result <- NULL
                         funerror <- NULL
                         funwarnings <- NULL
                         try(withCallingHandlers({

                             binArgList <- unlist(lapply(lapply(strsplit(\"%s\",\";\")[[1]], as.hexmode), as.raw))
                             argList <- as.list(unserialize(binArgList))

                             if (exists(\"InputDataSet\") && nrow(InputDataSet)!=0)
                             {
                                argList <- c(list(%s = InputDataSet), argList)
                             }

                             funwarnings <- capture.output(
                                 output <- capture.output(
                                     result <- do.call(%s, argList)
                                     ),
                                 type=\"message\")

                         }, error = function(err)
                         {
                            funerror <<- err
                         }
                         ), silent = TRUE)

                         options(warn=oldWarn)

                         serializedResult <- as.character(serialize(list(result, output, funwarnings, funerror), NULL))
                         OutputDataSet <- data.frame(returnVal=serializedResult, stringsAsFactors=FALSE)
                         list(result = result, output = output, warnings = funwarnings, errors = funerror)
                         ", funcName, funcBody, paste0(binArgs,collapse=";"), inputDataName, funcName)

    # Call the spees builder to wrap the function; needs the returnVal resultset
    #
    speesBuilder(speesBody, inputDataQuery, languageName=languageName, withResults = TRUE)
}
