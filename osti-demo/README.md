# Loading OSTI Data

These are some raw notes on the process of dumping data from OSTI 
into Solr and attempting to improve the speed of the scraping.

https://www.lanl.gov/library/find/reports/osti.php
says there are 3M citations and about an third have links to full text.

Docs can be found at: https://www.osti.gov/api/v1/docs, which
is where you get if you just go to www.osti.gov anwyay.

Page 1 of a sample search with output in json to file records is:

```
curl -H 'Accept: application/json' \
    --output records.json \
    --dump-header records.headers \
    https://www.osti.gov/api/v1/records
```

I dump the headers so that I can see the HATEOS Link header.
Plus, now we can use the received headers as the cookie jar to 
keep session id for subsequent searches?

Try '?sort=entry_date&order=desc' or '?publication_date_start=YESTERDAY&publication_date_end=TODDAY'
where YESTERDAY and TODAY are YYYY-MM-DDTHH:MM:SSZ formatted date/time strings.
The either might be better for a audit to see if any new entries were back-dated?

And to pretty print on linux, ``cat records.json | jq .``

Does searching for individual osti_id's yield any additional data?  Nope, so no need for a 2-phase crawl to flesh out osti_id's found on the first pass.

Sorting just isn't working for me, returns no records.  Putting sort field name in quotes and upper casing it doesn't work either.  Hmmm.

Using
entry_start_date/entry_end_date pair returns page 1 of 158421 pages, which is the same number of pages if
there was no filter.  Hmmm.  Aha, they don't want the full date, just MM/DD/YYYY.  Poor design?
Nope, that doesn't work either.
Hmm, lets try the session cookie approach?  Adding --cookie-jar and --silent to the curl command.

Now I can get the first page for a given date, so I wrote a program to estimate the volume the datafeed would entail.  
Size of 20 json records times the number of pages from the last page Link in the link headers
gives an estimate of bytes for that day.  Note: some days have no entries, but they are likely weekends
or holidays.

Investigate 6/20/2020!  Aha, if there is only one page, then the Link: header has no value but is present.

See osti-demo/estimate_volume_by_month.pl.

How about the same strategy by year?
Oddly, the number of pages found in 2020 is about 20k, but the by year for 2020 says 11k?
I can imagine almost 365 extra, but not 9k extra.  Hmmm.

Is my start date/end date range inclusive?  Yes, so that means I've got 365 days of data double counted.  D'oh.
Just query by day, and fix the year query to query up to 12/31.

So, in the last year I'm estimating 507 MB of data.  Perhaps 6GB total?
Aside: now that I've loaded all of the data, it turns out to be 310168 citations and 5.56gb total.
but that may also be counting the deleted but not garbage collected citations loaded twice?

Well, perhaps it is time to start dumping files for whole days and looking for dups?
Can I post them into Solr to make them searchable?
Can I hook up a blacklight to the Solr to use its GUI to search?

Next step, write a program that retrieves page 1 for a given day and reads its headers to find out how
many pages, then loads it into solr.  Then, for each of the remaining pages, gets them and load them
into Solr.

Use the Docker quickstart guide for Solr to add a core for 'osti'.
Says to run: 

```
docker run -d -v "$PWD/solrdata:/var/solr" -p 8983:8983 --name my_solr solr:8 solr-precreate osti
```

Once done, verify with GUI.

And then to load each json file run: 

```
docker exec -it my_solr post -c osti @FILE
```

First load of 11/4/20 was 185 pages, took 15 minutes, but had issues with one field.
Second load of same day took

Seems like, since Solr assigns the ids, that posting the same content multiple
times enters it multiple times.
8283 before 4th run on 11/4 data, see if it moves, 15, 10, 7 minutes
dj@filer /tmp $ # but now 11024 and 7 minutes. 13765 8m - duplicates are stored?

Can I get the schema to treat some osti data as the primary key?
Add a 'id' column to each before loading?

Also, journal_issue attribute needs to be string, not integer as auto detected.
Also patent_number.  The GUI says the schema says they are both org.apache.solr.schema.LongPointField

So, start over with clean solrdata directory.  

docker run and solr-precreate the osti core.
docker exec a shell, find the managed-schema file and change the unique id to osti_id
and the types of journal_issue and patent_number.
    but - if not data yet added, will there even be a schema file yet?
Note: just cd to the solrdata directory in the host.

Change /var/solr/data/osti/conf/managed-schema:
113c113
<     <field name="id" type="string" indexed="true" stored="true" required="true" multiValued="false" />
---
>     <field name="osti_id" type="string" indexed="true" stored="true" required="true" multiValued="false" />
169c169
<     <uniqueKey>id</uniqueKey>
---
>     <uniqueKey>osti_id</uniqueKey>

Then stop/restart but leave off the solr-precreate osti.

Check health on the GUI, seems good.

Then load a page of data and change the schema:

first run, 9m21s, still failing 2 fields above.
edit file from host again, fix those 2 fields to text. 

Change /var/solr/data/osti/conf/managed-schema:
468c468
<   <field name="journal_issue" type="plongs"/>
---
>   <field name="journal_issue" type="text_general"/>
476c476
<   <field name="patent_number" type="plongs"/>
---
>   <field name="patent_number" type="text_general"/>
579c579
< </schema>
\ No newline at end of file
---
> </schema>

Stop/start the container to make sure the changes are seen.  Load
a day's data again and hope for no errors.

Maybe add these fields when fixing the unique id and before loading the first data?

Argh, journal_volume too.  I'll be slowly finding fields to fix this way?
Maybe go find and change all plongs pre-emtively?

Now 11/4's data loads with no errors in 7m26s.  3699 loaded (was expecting
185 * 20 = 3650-3670?

Try again to make sure they stay unique.  Yes, max docs got up, deleted too.
but Num docs is correct.

A script that can load one day's data it useful to run daily, or even multiple
times daily to ensure that we've indexed all data for that day.  But it is
harder to manage to load, say, a year's data.  So, Let's modify the script to
be able to load a calendar year at a time.

2020 has 10999 pages on 11/6, at about 7m/day and 220 odd days (no weekends)
it could take a whole day to load a year.

Loaded 2020 (10999 pages) in:

output of time goes here.

## Future work 

Top says the single threaded version causes the Solr daemon to mostly use ~5% of cpu.
So, try 10 threads in parallel?

Even if we don't have multiple Solr instances running, perhaps the year loader could take
additional arguments for how many threads to run in parallel?
Then each thread could load its share of the total pages for the year.

* Thread 0 would start at page 0 and step forward by total threads.
* Thread 1 would start at page 1 and step forward by total threads.
* etc.

So that all pages get loaded once.  

And for further speed gains (when Solr is running on more than one physical server),
perhap each thread could also target a separate Solr instance?  But don't expect too
much of a gain now with each instance of the solr server running on my single 
compute node, either as a member of a Docker swarm or in its own VM.

All of 2006 should be in, 353 pages, let's benchmark (2-core machine):
first run to get all in on top of 2020... 3m50s

 64 threads 216 real	3m36.832s user	0m29.374s sys	0m20.684s
 32 threads 217 real	3m37.530s user	0m28.794s sys	0m18.413s
 16 threads 221 real	3m41.500s user	0m28.637s sys	0m17.432s
  8 threads 225 real	3m45.545s user	0m28.826s sys	0m17.369s <- knee of curve?
  4 threads 270 real	4m30.716s user	0m31.248s sys	0m17.592s
  2 threads 470 real	7m50.225s user	0m21.612s sys	0m11.184s <- died the first time though
  1 threads 805 real	13m25.652s user	0m38.675s sys	0m19.917s

So, 8 threads is the knee of the curve where additonal concurency isn't buying us much throughput.
Let's load the rest of the years with 8 threads?

Aha, name resolution fails for brief periods, add retries with sleeps.  Try 3 retries with 1 second between.
Not enough, try 5 retries with sleeps of retries squared.  1 4 9 16 25 for a total of 55 seconds.
Internet is so bad that all 8 threads died on 2012

Loading everything into a single Solr with replication (I thin).  Try again with a docker swarm of 3
shards with 2 replicas?  Break dependence on curl and docker?  It isn't entirely clear where the bottleneck
is.

     pages time output
2007   739 real	7m53.485s user	0m58.901s sys	0m36.612s
2008 34345 real	518m7.249s user	47m48.057s sys	29m2.652s
2009 34548 real	495m11.598s user 48m46.890s sys	29m19.318s
2010  7992 real	86m12.986s user	10m45.532s sys	6m32.278s
2011  6159 real	65m57.691s user	8m16.540s sys	4m55.186s
2012  3929 real	42m22.549s user	5m12.693s sys	3m14.335s <- internet failed so all 8 threads died on first try
2013  4314 real	46m38.017s user	5m48.796s sys	3m30.592s
2014  3112 real	33m15.238s user	4m9.982s sys	2m33.881s
2015  3613 real	39m47.407s user	4m49.865s sys	2m59.784s <- hung waiting to join threads on first try?
2016 36890 real	465m55.393s user	48m59.520s sys	30m10.361s
2017  4067 real	43m38.957s user	5m26.904s sys	3m18.775s
2018  3870 real	42m48.327s user	5m8.450s sys	3m10.170s
2019  3490 real	39m16.387s user	4m36.904s sys	2m49.332s
2020 11095 real	121m26.063s user	15m1.413s sys	9m8.951s<- partial year up to 11/8

try rows=100 and re-do 2014 (5x times fewer curl/post calls)
2014   623 real	6m59.615s user	0m52.164s sys	0m31.766s

try rows=1000 and re-do 2014
2014    63 real	1m12.921s user	0m8.929s sys	0m5.653s

try rows=2000 and re-do 2014 
2014    32 real	1m6.293s user	0m7.611s sys	0m4.103s

try rows=3000 and re-do 2014 
2014    21 real	1m15.563s user	0m4.122s sys	0m3.124s

but 4000 still says 21 pages, so the limit is 3000.

trying rows=10000 didn't return the right number of pages, suspect a 3000-ish limit?

So, using separate curl and docker/post processes is a bottleneck on this slow linux machine.
Hmm, re-do benchmarks with a range of threads and row-sizes?

Get rid of curl altogther using the Perl HTTP::Request and Apache::Solr modules.

My local perl is missing Apache::Solr::Json, so put it in a docker container so that we can 
cpanm install Apache::Solr::Json?

cpan -T Net::SSLeay is also needed.

In the meantime, benchmarks are
faster with 8 threads and 3000 rows per page on compute node:

2006    27
2007    43
2008 21m33
2009 19m59 <- some errors
2010  6m13
2011  5m20
2012  2m46
2013  3m09
2014  1m57
2015  2m50
2016 28m55
2017  3m50
2018  3m32
2019  2m58
2020 10m22

Maybe that is fast enough?  Little need to go much faster if we can reload
the whole data set in under 2 hours.
