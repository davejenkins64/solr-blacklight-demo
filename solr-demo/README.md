# solr-demo

These are some raw notes on experimenting with a Solr docker image.

## solr

The first step is to get Solr running locally.  
My strategy for most things it to run docker containers if possible.  
It seems that for Solr, it is possible!
Sure enough, there is an official docker container on dockerhup called solr.
https://hub.docker.com/\_/solr

Which says to:

```
docker pull solr
docker run -p 8983:8983 -t solr to start
```

Run output says:

1. uses jetty and jvm 11

2. some things are missing or failed to start, 

```
The currently defined JAVA_HOME (/usr/local/openjdk-11) refers to a location
where java was found but jstack was not found. Continuing.
OpenJDK 64-Bit Server VM warning: Failed to reserve shared memory. (error = 1)
OpenJDK 64-Bit Server VM warning: Failed to reserve shared memory. (error = 1)
OpenJDK 64-Bit Server VM warning: Failed to reserve shared memory. (error = 1)
2020-10-21 16:45:34.668 WARN  (main) [   ] o.e.j.x.XmlConfiguration Ignored arg: <Arg name="threadpool">
    <New id="threadpool" class="com.codahale.metrics.jetty9.InstrumentedQueuedThreadPool"><Arg name="registry">
        <Call id="solrJettyMetricRegistry" name="getOrCreate" class="com.codahale.metrics.SharedMetricRegistries"><Arg>solr.jetty</Arg></Call>
      </Arg></New>
  </Arg>
    ...
2020-10-21 16:45:47.430 WARN  (main) [   ] o.e.j.u.s.S.config Trusting all certificates configured for Client@396ef8b2[provider=null,keyStore=null,trustStore=null]
2020-10-21 16:45:47.431 WARN  (main) [   ] o.e.j.u.s.S.config No Client EndPointIdentificationAlgorithm configured for Client@396ef8b2[provider=null,keyStore=null,trustStore=null]
2020-10-21 16:45:47.728 WARN  (main) [   ] o.e.j.u.s.S.config Trusting all certificates configured for Client@6573d2f7[provider=null,keyStore=null,trustStore=null]
2020-10-21 16:45:47.728 WARN  (main) [   ] o.e.j.u.s.S.config No Client EndPointIdentificationAlgorithm configured for Client@6573d2f7[provider=null,keyStore=null,trustStore=null]
2020-10-21 16:45:47.884 WARN  (main) [   ] o.a.s.c.CoreContainer Not all security plugins configured!  authentication=disabled authorization=disabled.  Solr is only as secure as you make it. Consider configuring authentication/authorization before exposing Solr to users internal or external.  See https://s.apache.org/solrsecurity for more info
```

3. may not be secure.

"See https://s.apache.org/solrsecurity for more info"

To test, just point a browser at <host IP>:8983.

The GUI seems to want me to add a "Core", at the bottom of the left navigation
pane "No cores available" "Go and create one"

But wait, there is a better way to run this as a single node with
persistent data:

```
$ mkdir solrdata
$ docker run -d -v "$PWD/solrdata:/var/solr" -p 8983:8983 --name my_solr solr:8 solr-precreate gettingstarted
```

This creates a cor called gettingstarted, I used osti for my demo.

Note: I had to chmod og+w solrdata too, the container runs as a userid 
8983/groupid 8983?  Another solution would be to create that user/group on the
host and just chmod g+w?

And to load some sample data:

```
$ docker exec -it my_solr post -c gettingstarted example/exampledocs/manufacturers.xml
```

You can also post JSON data.  Output looks like:

```
usr/local/openjdk-11/bin/java -classpath /opt/solr/dist/solr-core-8.6.3.jar -Dauto=yes -Dc=gettingstarted -Ddata=files org.apache.solr.util.SimplePostTool example/exampledocs/manufacturers.xml
SimplePostTool version 5.0.0
Posting files to [base] url http://localhost:8983/solr/gettingstarted/update...
Entering auto mode. File endings considered are xml,json,jsonl,csv,pdf,doc,docx,ppt,pptx,xls,xlsx,odt,odp,ods,ott,otp,ots,rtf,htm,html,txt,log
POSTing file manufacturers.xml (application/xml) to [base]
1 files indexed.
COMMITting Solr index changes to http://localhost:8983/solr/gettingstarted/update...
Time spent: 0:00:01.199
```

That worked, I see 11 manufacturers records when I search *.*.
in the GUI.

Need to stop (docker kill/docker rm) that container because of 
container name and port conflicts with the next demo.

How about the single image demo?

```
$ docker run --name solr_demo -d -p 8983:8983 solr:8 solr-demo
```

Runs a different data set, this time with 46 items.

### Future Work

#### Docker Swarms

Back to original demo, but starting up using docker-compose and its
docker-compose.yml and 'docker-compose up -d'.  Note:

```
WARNING: The Docker Engine you're using is running in swarm mode.

Compose does not use swarm mode to deploy services to multiple nodes in a swarm. All containers will be scheduled on the current node.

To deploy your application across the swarm, use `docker stack deploy`.
```

So, perhaps it is time to get multiple VMs running, each as a member of
a docker swarm before working on the cluster install below.

Also, this only partially worked.  No getting started data got loaded,
perhaps the data mount is wrong?  Added 'driver: local' at end of yaml file.
Nope.  Clear data dir and start again?

The data isn't getting loaded when the volume is created by docker compose.
Race condition in the compose file?  Just load data manually using
new container name:

```
docker exec -it solr-demo_solr_1 post -c gettingstarted example/exampledocs/manufacturers.xml
```

#### Clusters

And the harder way would be in a cluster.

The cluster config sample yaml loads 3 Solr containers and 3 zookeeper 
containers.
Both swarms and clusters will wait for another day.

### Testing

The blacklight.org wiki wants to verify java version > 1.8
So, with the solr container running:

```
docker exec -it <container id> /bin/bash
java --version
```

Says: 11.0.8, so we are good.

### Loading Data

Perhaps this page had additional information about posting data
into Lucene/Solr:

`https://lucene.apache.org/solr/guide/8_5/post-tool.html`

From the source code, create a collection.  For any fields in the input
data that Solr miss-classifies, fix the schema with POST.

```
solr*/*/var/tmp/solr-8.6.1/solr/example/films/README.txto

curl http://localhost:8983/solr/films/schema -X POST -H 'Content-type:application/json' --data-binary '{
    "add-field" : {
        "name":"name",
        "type":"text_general",
        "multiValued":false,
        "stored":true
    },
    "add-field" : {
        "name":"initial_release_date",
        "type":"pdate",
        "stored":true
    }
}'
```

So, in this example, the "name" and "initial_release_date" fields must
not have been classified correctly.  In the case of films, maybe name
was triggering a first/middle/last parsing we didn't want and 
initial_release_date should treat the date as a date?

The input data is XML, JSON and CSV.  The JSON file is an array of films.
One JSON record looks like:

```
  {
    "id": "/en/harry_potter_and_the_order_of_the_phoenix_2007",
    "initial_release_date": "2007-06-28",
    "name": "Harry Potter and the Order of the Phoenix",
    "genre": [
      "Family",
      "Mystery",
      "Adventure Film",
      "Fantasy",
      "Fantasy Adventure",
      "Fiction"
    ],
    "directed_by": [
      "David Yates"
    ]
  }
```

But in my case, since I need to change the uniqueId for the OSTI data
set I just made edits to the managed-schema to add the 3 fields
that would be miss-detected at that time.

So, at this point Solr is running as a single container.  Let's load
some data.

