#!/usr/bin/perl -w
use strict;
use FileHandle;

# for a given day of the last year
# curl the first page of osti entries as a json file
# then load into solr with post.

my $osti = "https://www.osti.gov/api/v1/records";
my $solr = "http://localhost:8983/solr/osti";

# TODO - make up tmp file names
my $header = "/tmp/$$.head";
my $json_dir = $ENV{'HOME'} . "/solr-demo/solrdata";
my $json = $json_dir ."/$$.json";
my $json_in_client = "../../var/solr/$$.json";
my $cookie = "/tmp/$$.cookie";

# TODO - use a request/response object instead of curl

my $start = shift(@ARGV) || die "usage: $0 MM/DD/YYYY\n";;
if ($start !~ m#^\d\d/\d\d/\d\d\d\d$#) {
    die "usage: $0 MM/DD/YYYY\n";;
}

# get page 1 for a given day
my $ret = system("curl --silent --cookie-jar $cookie -H 'Accept: application/json' --output $json --dump-header $header '$osti\?entry_date_start=$start\&entry_date_end=$start'");
if ($ret) {
    die "curl returned " . ($ret >> 8) . "\n";
}

# get the number of pages of records for that day from the headers
my $fh = FileHandle->new("<$header") || die "can't read $header: $!\n";
my $pages = 0;
while (my $line = $fh->getline()) {
    if ($line =~ m/^Link:(.*)/) {
        my $value = $1;
        # Links are a comma separated list
        foreach my $link (split(/,/, $value)) {
            # and we want the one that lets us access the last page
            if ($link=~ m/; rel="last"/) { 
                if ($link =~ m/\&page=(\d+)>/) {
                    $pages = $1;
                }
            }
        }
        # if we see a Link header but it has no values, that's 1 page
        $pages = 1 if ((0 == $pages) && ($value =~ m/ \r?$/));
    }
}

# load page 1 with curl POST to Solr
$ret = system("docker exec -it my_solr post -c osti $json_in_client");
if ($ret) {
    die "curl POST of page 1 returned " . ($ret >> 8) . "\n";
}

# get the rest of the pages
for (my $i = 2; $i <= $pages; $i++) {
    # get page 1 for a given day
    $ret = system("curl --silent --cookie-jar $cookie -H 'Accept: application/json' --output $json '$osti\?entry_date_start=$start\&entry_date_end=$start\&page=$i'");
    if ($ret) {
        die "curl of page $i returned " . ($ret >> 8) . "\n";
    }

    # load page 1 with curl POST to SOLR
    $ret = system("docker exec -it my_solr post -c osti $json_in_client");
    if ($ret) {
        die "curl POST of page $i of $pages returned " . ($ret >> 8) . "\n";
    }
}
chdir("/tmp");
unlink($header);
unlink($cookie);
chdir($json_dir);
unlink($json);

# End of file
