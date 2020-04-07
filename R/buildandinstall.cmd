pushd .
cd ..
R -e "install.packages('RODBCext', repos='https://mran.microsoft.com/snapshot/2019-02-01/')"
R CMD INSTALL --build R
R CMD INSTALL --build R sqlmlutils.tar.gz
mv sqlmlutils_*.zip R/dist
mv sqlmlutils_*.tar.gz R/dist
popd
