#' @section Executing in SQL:
#'
#'  \itemize{
#'   \item \code{\link{connectionInfo}}: Creates a connection string from a set of parameters
#'
#'   \item \code{\link{executeScriptInSQL}}: Executes a script file inside SQL
#'
#'   \item \code{\link{executeFunctionInSQL}}: Executes a user function inside SQL
#'
#'   \item \code{\link{executeSQLQuery}}: Executes a SQL query and returns the resultant table
#' }
#'
#' @section Stored Procedures:
#' \itemize{
#'   \item \code{\link{createSprocFromFunction}}: Creates a stored procedure from a custom R function
#'
#'   \item \code{\link{createSprocFromScript}}: Creates a stored procedure from a custom R script file
#'
#'   \item \code{\link{dropSproc}}: Drops a stored procedure from the database
#'
#'   \item \code{\link{executeSproc}}: Executes a stored procedure that is already in the database
#'
#'   \item \code{\link{checkSproc}}: Checks if a stored procedure is already in the database
#' }
#'
#' @section Package Management:
#'
#' \itemize{
#'   \item \code{\link{sql_install.packages}}: Installs packages on a SQL Server
#'
#'   \item \code{\link{sql_remove.packages}}: Removes packages from a SQL Server
#'
#'   \item \code{\link{sql_installed.packages}}: Enumerates the installed packages on a SQL Server
#' }
#' @keywords package
"_PACKAGE"
#> [1] "_PACKAGE"
