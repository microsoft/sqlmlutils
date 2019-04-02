pushd .
cd ..
R -e "install.packages('RODBCext', repos='https://cran.microsoft.com')"
R CMD INSTALL --build R
mv sqlmlutils_*.zip R/dist
popd
