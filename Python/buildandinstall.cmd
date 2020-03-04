python.exe setup.py sdist --formats=zip
python.exe -m pip install --upgrade --upgrade-strategy only-if-needed dist\sqlmlutils-0.7.3.zip
