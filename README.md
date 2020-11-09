# solr-blacklight-demo

Demonstration of search with Solr loaded with OSTI data and blacklight.org

## solr

The first step is to get Solr running locally.  
Sure enough, there is an official docker container on dockerhub called solr.

```
docker pull solr
docker run -p 8983:8983 -t solr to start
```

To test, just point a browser at <host IP>:8983.

The GUI seems to want me to add a "Core", at the bottom of the left navigation
pane "No cores available" "Go and create one"

But wait, there is a better way to run this as a single node with
persistent data:

```
$ mkdir solrdata
$ docker run -d -v "$PWD/solrdata:/var/solr" -p 8983:8983 --name my_solr solr:8 solr-precreate gettingstarted
```

This creates a core called gettingstarted, I used osti for my demo.

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

### Future Work

It would be interesting to try running multiple Solr isntances with
sharding and replication.  It seems that we can run them as a docker swarm,
might also be educational to run them in separate VMs or under kubernetes.

### Testing

The blacklight.org wiki wants to verify java version > 1.8
So, with the solr container running:

```
docker exec -it <container id> /bin/bash
java --version
```

Says: 11.0.8, so we are good.

So, at this point Solr is running as a single container.  We have
created a core called osti.  Let's load some data.

## Loading OSTI Data

If we want to make a data stream searchable, we'll want to load
it into Solr.  First, how big is the stream?  How many items total, per year,
per day?  How much volume?  My test machine is somewhat limited, if
the data set is huge, it won't handle it.  

Let's start by estimating the volume by day for the past year.

See:
[osti-demo/estimate_volume_by_day.pl](osti-demo/estimate_volume_by_day.pl)

This is a perl script that uses curl to find the total set of pages
and gets the first page (20 rows) for each day for the last year.  
We use the number of
pages times the size of the sample page to estimate volume.

Seems to say:

```
11/05/2020 130 60304 = 7655 KB
11/04/2020 185 31845 = 5753 KB
11/03/2020 150 62203 = 9111 KB
11/02/2020 198 32507 = 6285 KB
11/01/2020 0 0 = 0 KB
10/31/2020 0 0 = 0 KB
    ...
11/12/2019 7 47855 = 327 KB
11/11/2019 12 53887 = 631 KB
11/10/2019 0 0 = 0 KB
11/09/2019 0 0 = 0 KB
11/08/2019 7 39590 = 270 KB
11/07/2019 10 53346 = 520 KB
TOTAL 11801 pages and 524062.436523438 KB
```

So, perhaps ~10% of all documents were entered in the last year?

Next, let's verify the volume of the entire feed:

See:
[osti-demo/estimate_volume_by_year.pl](osti-demo/estimate_volume_by_year.pl)

This script simply changes the start day to 01/01 and the end day to 12/31
for each year.  Output like:

```
01/01/2020 10999 30000 = 314 MB
01/01/2019 3494 30371 = 101 MB
01/01/2018 3872 27575 = 101 MB
01/01/2017 4067 37423 = 145 MB
01/01/2016 36890 29713 = 1045 MB
01/01/2015 3614 38560 = 132 MB
01/01/2014 3112 48782 = 144 MB
01/01/2013 4315 47917 = 197 MB
01/01/2012 3929 51687 = 193 MB
01/01/2011 6159 45527 = 267 MB
01/01/2010 7992 51494 = 392 MB
01/01/2009 34548 54678 = 1801 MB
01/01/2008 34345 42356 = 1387 MB
01/01/2007 739 34158 = 24 MB
01/01/2006 353 40095 = 13 MB
01/01/2005 0 0 = 0 MB
TOTAL 6263
```

So, the OSTI system was probably created in 2006 and the
bulk of the data was migrated in during 2008-2009.
Estimating 6.2GB, my lab can handle that.

Next we want to be able to grab a single day of data from OSTI
and insert it into Solr.  The idea is, that if this is fast enough,
and inserting duplicates into Solr just overwrites what is there,
that we can run the single-day script periodically throughout the
day to keep our cache up to date.  And we can also run it as an
audit to make sure no operator back-dated any new entries in OSTI.

See:
[osti-demo/estimate_load_day.pl](osti-demo/load_day.pl)

But loading by day would get tedious for the initial bulk load.
How about we rewrite to handle an entire year:
[osti-demo/estimate_load_year.pl](osti-demo/load_year.pl)

This was still too slow, so how about we throw Perl threads at
the problem?  
[osti-demo/estimate_load_year_fast.pl](osti-demo/load_year_fast.pl)

8 threads is about 3-5 times faster.  But it turns out that what
is really slowing us down is all of the ``curl`` and ``docker exec post -c``
processes starting/stopping.  Increasing the number of rows in the curl
GET from 20 to 3000 yields a 16x improvement.

Next steps, try to use the Perl HTTP::Request/JSON:XS/Apache::Solr modules
to completely avoid forking processes.  Put it all in a container for
portability.  I'm calling this load_solr.pl but haven't finished it.

## blacklight.org

Consistent with my strategy of containerizing as much as possible, let's
see if we can build a container for blacklight to run in, that can talk to
the Solr container.  
See:
[blacklight-org-demo/Dockerfile](blacklight-org-demo/Dockerfile).

At this point, it builds and runs, but the default MARC schema isn't consistent
with the OSTI schema.  Next step is to reconcile this so that we can
search OSTI data using blacklight.

