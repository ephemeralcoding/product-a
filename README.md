# Fix
1. Fixa paths i byggskript (X)
2. Bygg en venv från wheels och exekvera ansible ifrån den (X)
3. Bryt ut bygget ifrån produkt repot
3. Ladda ner dependencies ifrån repo beroende på vilka paket
4. Testa om installation fungerar (X)
4. Kolla på komprimering av tarballen
4. Fundera ut på en temp katalog för byggen/wheels och grejor
4. Konverta byggscriptet till en container
5. Konvertera till en CI/CD pipeline
6. Kör tester i en vagrant box
7. Generera en SBOM
8. fixa gitignore på roles och artifacts i produkt repot (X)
9. venven ska inte skickas med bundle (X)
10. VARS NOT SET IN DEFAULT för rollerna (X)
11. HASHSUM
12. Signera
13. Disable default repos
14. Använd ett fetch skript för dependencies alltså - parsa ansible roller för paket (X)
15. Fetch scriptet failar ifall den inte har repot enablat.
16. hitta ett sätt som disablar remote repos och enablar custom repot.
17. Paketera i en RPM och printa ut ett manifest
18. Var ska remote repona disablas?
19. Vart ska custom repot läggas?
20. Lägg till stöd för att köra olika configs i ansible - dev, prod. etc.


# Notes
* tänk på metadatan - default not set och en custom fil
* Tänk på paths
* Beskrivning för hur man skapar en ny roll
* Fundering ifall det vore rimligare att artifakterna droppades in direkt i files foldern?
* Tänk på fetch av dependencies om state står som present kontra absent?
* Tänk på ifall man ska skriva över defaults variabler ifrån roles i en global vars-fil så finns det risk för konflikt
* Vore nice med en parser som bakar in alla default vars från roller till global vars-filen
* Tänk på Fetch scriptet failar ifall den inte har repot enablat.
* Tänk på custom repo url och cert på jobb
* Tänk på ett sätt som disablar remote repos och enablar custom repot.
* I install scriptet så hårdhackas pathen där custom repot kopieras till.


Containerize:
1. Bygg en image med alla verktyg som krävs
2. Hämta produkt-repo från git
3. Hämta och kör byggskript
4. paths måste stämma för skripten.