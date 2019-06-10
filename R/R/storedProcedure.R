# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.


#'
#'Create a Stored Procedure
#'
#'This function creates a stored procedure from a function
#'on the database and return the object.
#'
#'
#'@param connectionString character string. The connectionString to the database
#'@param name character string. The name of the stored procedure
#'@param func closure. The function to wrap in the stored procedure
#'@param inputParams named list. The types of the inputs,
#'where the names are the arguments and the values are the types
#'@param outputParams named list. The types of the outputs,
#'where the names are the arguments and the values are the types
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'
#'@section Warning:
#'You can add output parameters to the stored procedure
#'but you will not be able to execute the procedure from R afterwards.
#'Any stored procedure with output params must be executed directly in SQL.
#'
#'@examples
#'\dontrun{
#' connectionString <- connectionInfo()
#'
#' ### Using a function
#' dropSproc(connectionString, "fun")
#'
#' func <- function(arg1) {return(data.frame(hello = arg1))}
#' createSprocFromFunction(connectionString, name = "fun",
#'                         func = func, inputParams = list(arg1="character"))
#'
#' if (checkSproc(connectionString, "fun")) {
#'     print("Function 'fun' exists!")
#'     executeSproc(connectionString, "fun", arg1="WORLD")
#' }
#'
#' ### Using a script
#' createSprocFromScript(connectionString, name = "funScript",
#'                       script = "path/to/script", inputParams = list(arg1="character"))
#'
#'}
#'
#'
#'
#'@seealso{
#'\code{\link{dropSproc}}
#'
#'\code{\link{executeSproc}}
#'
#'\code{\link{checkSproc}}
#'}
#'
#'@return Invisibly returns the script used to create the stored procedure
#'
#'@describeIn createSprocFromFunction Create stored procedure from function
#'@export
createSprocFromFunction <- function (connectionString, name, func,
                                     inputParams = NULL, outputParams = NULL,
                                     getScript = FALSE) {

    possibleTypes <- c("posixct", "numeric", "character", "integer", "logical", "raw", "dataframe")

    lapply(inputParams, function(x) {
        if (!tolower(x) %in% possibleTypes) stop("Possible types are POSIXct, numeric, character, integer, logical, raw, and DataFrame.")
    })
    lapply(outputParams, function(x) {
        if (!tolower(x) %in% possibleTypes) stop("Possible types are POSIXct, numeric, character, integer, logical, raw, and DataFrame.")
    })

    inputParameters <- methods::formalArgs(func)

    if (!setequal(names(inputParams), inputParameters)){
        stop("inputParams and function arguments do not match!")
    }

    procScript <- generateTSQL(func = func, spName = name, inputParams = inputParams, outputParams = outputParams)


    if(getScript) {
        return(procScript)
    }

    tryCatch({
        register(procScript, connectionString = connectionString)
    }, error = function(e) {
        stop(paste0("Failed during registering procedure ", name, ": ", e))
    })
}

#'@describeIn createSprocFromFunction Create stored procedure from script file, returns output of final line
#'
#'@param script character string. The path to the script to wrap in the stored procedure
#'@export
createSprocFromScript <- function (connectionString, name, script,
                                   inputParams = NULL, outputParams = NULL,
                                   getScript = FALSE) {

    if (file.exists(script)){
        print(paste0("Script path exists, using file ", script))
    } else {
        stop("Script path doesn't exist")
    }

    text <- paste(readLines(script), collapse="\n")

    possibleTypes = c("posixct", "numeric", "character", "integer", "logical", "raw", "dataframe")

    lapply(inputParams, function(x) {
        if (!tolower(x) %in% possibleTypes) stop("Possible input types are POSIXct, numeric, character, integer, logical, raw, and DataFrame.")
    })
    lapply(outputParams, function(x) {
        if (!tolower(x) %in% possibleTypes) stop("Possible output types are POSIXct, numeric, character, integer, logical, raw, and DataFrame.")
    })

    procScript <- generateTSQLFromScript(script = text, spName = name, inputParams = inputParams, outputParams = outputParams)

    if(getScript) {
        return(procScript)
    }

    tryCatch({
        register(procScript, connectionString = connectionString)
    }, error = function(e) {
        stop(paste0("Failed during registering procedure ", name, ": ", e))
    })

    invisible(procScript)
}


#'Drop Stored Procedure
#'
#'@param connectionString character string. The connectionString to the database
#'@param name character string. The name of the stored procedure
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'
#'@examples
#'\dontrun{
#' connectionString <- connectionInfo()
#'
#' dropSproc(connectionString, "fun")
#'
#' func <- function(arg1) {return(data.frame(hello = arg1))}
#' createSprocFromFunction(connectionString, name = "fun",
#'                         func = func, inputParams = list(arg1 = "character"))
#'
#' if (checkSproc(connectionString, "fun")) {
#'     print("Function 'fun' exists!")
#'     executeSproc(connectionString, "fun", arg1="WORLD")
#' }
#'}
#'
#'
#'@seealso{
#'
#'\code{\link{createSprocFromFunction}}
#'
#'\code{\link{executeSproc}}
#'
#'\code{\link{checkSproc}}
#'}
#'
#'@importFrom RODBCext sqlExecute
#'@import RODBC
#'
#'@export
dropSproc <- function(connectionString, name, getScript = FALSE) {
    query = sprintf("DROP PROCEDURE %s", name)

    if(getScript) {
        return(query)
    }

    tryCatch({
        dbhandle <- odbcDriverConnect(connectionString)
        output <- sqlExecute(dbhandle, "SELECT OBJECT_ID (?)", name, fetch=TRUE)
        if (!is.na(output)) {
            output <- sqlQuery(dbhandle, sprintf("DROP PROCEDURE %s", name))
        } else {
            output <- "Named procedure doesn't exist"
        }
    }, error = function(e) {
        stop(paste0("Error dropping the stored procedure\n"))
    }, finally = {
        odbcCloseAll()
    })

    if (length(output) > 0) {
        print(output)
        return(FALSE)
    } else {
        print(paste0("Successfully dropped procedure ", name))
        return(TRUE)
    }
}

#'Check if Stored Procedure is in Database
#'
#'@param connectionString character string. The connectionString to the database
#'@param name character string. The name of the stored procedure
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'
#'@return Whether the stored procedure exists in the database
#'
#'@examples
#'\dontrun{
#' connectionString <- connectionInfo()
#'
#' dropSproc(connectionString, "fun")
#'
#' func <- function(arg1) {return(data.frame(hello = arg1))}
#' createSprocFromFunction(connectionString, name = "fun",
#'                         func = func, inputParams = list(arg1="character"))
#' if (checkSproc(connectionString, "fun")) {
#'     print("Function 'fun' exists!")
#'     executeSproc(connectionString, "fun", arg1="WORLD")
#' }
#'}
#'
#'
#'@seealso{
#'\code{\link{createSprocFromFunction}}
#'
#'\code{\link{dropSproc}}
#'
#'\code{\link{executeSproc}}
#'
#'}
#'
#'@importFrom RODBCext sqlExecute
#'@import RODBC
#'@export
checkSproc <- function(connectionString, name, getScript=FALSE) {

    query = c(sprintf("SELECT OBJECT_ID (%s, N'P')", name))

    if(getScript) {
        return(query)
    }

    tryCatch({
        dbhandle <- odbcDriverConnect(connectionString)
        output <- sqlExecute(dbhandle, "SELECT OBJECT_ID (?, N'P')", name, fetch = TRUE)
    }, error = function(e) {
        cat(paste0("Error executing the sqlExecute\n"))
    }, finally = {
        odbcCloseAll()
    })
    if (is.na(output)) {
        return(FALSE)
    } else {
        return(TRUE)
    }
}

#'Execute a Stored Procedure
#'
#'@param connectionString character string. The connectionString for the database with the stored procedure
#'@param name character string. The name of the stored procedure in the database to execute
#'@param ... named list. Parameters to pass into the procedure. These MUST be named the same as the arguments to the function.
#'@param getScript boolean. Return the tsql script that would be run on the server instead of running it
#'
#'@section Warning:
#'Even though you can create stored procedures with output parameters, you CANNOT execute them
#'using this utility due to limitations of RODBC.
#'
#'@examples
#'\dontrun{
#' connectionString <- connectionInfo()
#'
#' dropSproc(connectionString, "fun")
#'
#' func <- function(arg1) {return(data.frame(hello = arg1))}
#' createSprocFromFunction(connectionString, name = "fun",
#'                         func = func, inputParams = list(arg1="character"))
#'
#' if (checkSproc(connectionString, "fun")) {
#'     print("Function 'fun' exists!")
#'     executeSproc(connectionString, "fun", arg1="WORLD")
#' }
#'}
#'@seealso{
#'\code{\link{createSprocFromFunction}}
#'
#'\code{\link{dropSproc}}
#'
#'\code{\link{checkSproc}}
#'}
#'@importFrom RODBCext sqlExecute
#'@import RODBC
#'@export
executeSproc <- function(connectionString, name, ..., getScript = FALSE) {
    if (class(name) != "character")
        stop("the argument must be the name of a Sproc")

    res <- createQuery(connectionString = connectionString, name = name, ...)
    query <- res$query
    paramOrder <- res$inputParams
    df = data.frame(...)

    if(getScript) {
        return(query)
    }

    if (nrow(df) != 0 && ncol(df) != 0) {
        df <- df[paramOrder]
    }

    tryCatch({
        dbhandle <- odbcDriverConnect(connectionString)
        result <- sqlExecute(dbhandle, query, df, fetch = TRUE)
    }, error = function(e) {
        stop(paste0("Error in SQL Execution: ", e, "\n"))
    }, finally ={
        odbcCloseAll()
    })

    if (is.list(result)) {
        return(result)
    } else if (!is.character(result)) {
        stop(paste("Error executing the stored procedure:", name))
    } else {
        return(NULL)
    }
}

#
# Get the parameters of the stored procedure to create the query
#
#@param connectionString character string. The connectionString to the database
#@param name character string. The name of the stored procedure
#
#@return the parameters
#
getSprocParams <- function(connectionString, name) {
    query <- "SELECT 'Parameter_name' = name, 'Type' = type_name(user_type_id),
    'Output' = is_output FROM sys.parameters WHERE OBJECT_ID = ?"

    inputDataName <- NULL
    tryCatch({
        dbhandle <- odbcDriverConnect(connectionString)

        number <- sqlExecute(dbhandle, "SELECT OBJECT_ID (?)", name, fetch=TRUE)[[1]]

        params <- sqlExecute(dbhandle, query, number, fetch=TRUE)
        outputParams <- split(params,params$Output)[['1']]
        inputParams <- split(params,params$Output)[['0']]

        text <- paste0(collapse="", lapply(sqlExecute(dbhandle, "EXEC sp_helptext ?", name, fetch = TRUE), as.character))
        matched <- regmatches(text, gregexpr("input_data_1_name = [^,]+",text))[[1]]
        if (length(matched) == 1) {
            inputDataName <- regmatches(matched, gregexpr("N'.*'",matched))[[1]]
            inputDataName <- gsub("(N'|')","", inputDataName)
        }
    }, error = function(e) {
        cat(paste0("Error executing the sqlExecute\n"))
        odbcCloseAll()
        stop(e)
    }, finally ={
        odbcCloseAll()
    })
    list(inputParams = inputParams, inputDataName = inputDataName, outputParams = outputParams)
}

#Create the necessary query to execute the stored procedure
#
#@param connectionString character string. The connectionString to the database
#@param name character string. The name of the stored procedure
#@param ... The arguments for the stored procedure
#
#@return the query
#
createQuery <- function(connectionString, name, ...) {
    #Get and process params from the stored procedure in the database
    storedProcParams <- getSprocParams(connectionString = connectionString, name = name)
    params <- storedProcParams$inputParams
    inList <- c()

    if (!is.null(params)) {
        for(i in seq_len(nrow(params))) {
            parameter_outer <- params[i,]$Parameter_name
            parameter <- gsub('.{6}$', '', parameter_outer)
            parameter <- gsub('@','', parameter)
            type <- params[i,]$Type

            inList <- c(inList,parameter)
        }
    }
    inLabels <- NULL
    if (!(length(list(...)) == 1 && is.null(list(...)[[1]]))) {
        inLabels <- labels(list(...))
        if (!all(inLabels %in% inList)) {
            stop("You must provide named arguments that match the parameters in the stored procedure.")
        }
    }
    #add necessary variable declarations and value assignments

    query <- paste0("exec ", name)
    for(p in inList) {
        paramName <- p
        query <- paste0(query, " @", paramName, "_outer = ?,")
    }
    query <- gsub(",$", "", query)
    list(query=query, inputParams=inList)
}
