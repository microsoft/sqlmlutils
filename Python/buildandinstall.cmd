del /q dist\*
python.exe setup.py sdist --formats=zip
python.exe setup.py bdist_wheel
python.exe -m pip install --upgrade --upgrade-strategy only-if-needed --find-links=dist sqlmlutils
