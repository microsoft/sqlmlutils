pushd .
cd ..
R -e "install.packages('RODBCext', repos='https://ftp.osuosl.org/pub/cran/')"
R CMD INSTALL --build R
mv sqlmlutils_*.zip R/dist
popd
