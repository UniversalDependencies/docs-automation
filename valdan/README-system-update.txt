udvalidator: Problémy po aktualizaci systému na Ubuntu 22.04:

Perl (githook.pl, ale taky https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl):
- Bere se systémový z /usr/bin/perl, teď je to verze 5.34.0.
- Chyběl JSON::Parse
- Chyběl YAML
- Chyběl CGI (pro specify_deprel.pl a spol.)
(Použil jsem sudo cpan, aby se to nainstalovalo systémově a viděl to i uživatel www-data.)

Git:
Nově mu vadí, že část podstromu složky patří uživateli zeman a část www-data. Pomohlo tohle:
sudo git config --system --add safe.directory '*'

Python (validate.sh --> validate.py)
- Bere se systémový z /usr/bin/python3 ("python" bez čísla vůbec není k dispozici), teď je to verze 3.10.6.
- Chyběl modul regex
(Použil jsem sudo pip3 install regex, aby se to nainstalovalo systémově a viděl to i uživatel www-data. Řeklo mi to ale
WARNING: Running pip as the 'root' user can result in broken permissions and conflicting behaviour with the system package manager. It is recommended to use a virtual environment instead: https://pip.pypa.io/warnings/venv
Nicméně validátor už pak fungoval.)
