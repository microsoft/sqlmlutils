pushd .
cd ..
R -e "install.packages('RODBCext', repos='https://cran.rstudio.com')"
R CMD INSTALL --build R
mv sqlmlutils_0.5.0.zip R/dist
popd
