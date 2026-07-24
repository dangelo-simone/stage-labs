#usa il compose file del primo punto
docker compose up -d
docker compose ps
#check sito up, aggiungo post e  cambio tema così chè qualcosa di cui fare il dump


#dump db e copio contenuti da cartella wordpress a cartella che verrà usata>

docker compose exec db sh -c 'exec mariadb-dump -u root -pexample exampledb' > exampledb.sql

mkdir -p custom-build && cd custom-build
docker compose -f ../docker-compose.yml cp wordpress:/var/www/html/wp-content ./wp-content
mv ../exampledb.sql ./exampledb.sql


#build immagini
docker build -t custom-wordpress:v1 -f Dockerfile.wordpress .
docker build -t custom-mariadb:v1 -f Dockerfile.db .


#deploy senza volumi
docker compose -f ../docker-compose.yml down
docker compose -f docker-compose.custom.yml down -v
docker compose -f docker-compose.custom.yml up -d
