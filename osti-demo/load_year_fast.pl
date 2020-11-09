#!/usr/bin/perl -w
use strict;
use FileHandle;
use threads;

# for a given day of the last year
# curl the first page of osti entries as a json file
# then load into solr with post.

my $osti = "https://www.osti.gov/api/v1/records";
my $solr = "http://localhost:8983/solr/osti";

my $header = "/tmp/$$.head";
# FIXME file must end in json, don't put thread number after!
my $json_dir = $ENV{'HOME'} . "/solr-demo/solrdata";
my $json_root = "$$.json";
my $json_in_client_dir = "../../var/solr";
my $json_in_client_root = "$$.json";
my $cookie_root = "/tmp/$$.cookie";

### Subroutines
sub thread_main($$$$$$$$$$) {
    my ($thread_number, $total_threads, $pages, $osti, $start, $end, $cookie, $json_dir, $json_root, $json_in_client_dir) = @_;

    # let the other threads get going
    threads->yield();

    system("cp $cookie $cookie.$thread_number");
    $cookie .= '.' . $thread_number;
    my $json = "$json_dir/${thread_number}_${json_root}";
    my $json_in_client = "$json_in_client_dir/${thread_number}_${json_root}";

    # get the rest of the pages
    my $ret; # return code from system call
    for (my $i = $thread_number+1; $i <= $pages; $i += $total_threads) {
        next if (1 == $i); # first page already handled before starting threads

        print("\n\nWorking on page $i of $pages\n\n");
        my $worked = 0;
        for (my $j = 1; $j <= 5; $j++) {
            # get page 1 for a given day
            $ret = system("curl --silent --cookie-jar $cookie -H 'Accept: application/json' --output $json '$osti\?entry_date_start=$start\&entry_date_end=$end\&page=$i'");
            if ($ret) {
                warn "curl of page $i returned " . ($ret >> 8) . " sleeping $j squared seconds\n";
                sleep($j*$j);
            }
            else {
                $worked = 1;
                last;
            }
        }
        if (!$worked) {
            die "curl failed after 3 tries\n";
        }

        # load page 1 with curl POST to SOLR
        $ret = system("docker exec -it my_solr post -c osti $json_in_client");
        if ($ret) {
            die "curl POST of page $i of $pages returned " . ($ret >> 8) . "\n";
        }
    }
    chdir("/tmp");
    unlink($cookie);
    chdir($json_dir);
    unlink($json);
}

### Main
# TODO - use a request/response object instead of curl for both GET and POST

my $max_threads = shift(@ARGV) || die "usage: $0 threads YYYY\n";
if ($max_threads !~ /^\d+$/) {
    die "usage: $0 threads YYYY\n";
}
my $year = shift(@ARGV) || die "usage: $0 threads YYYY\n";;
if ($year !~ m#^\d\d\d\d$#) {
    die "usage: $0 threads YYYY\n";;
}
my $start = "01/01/$year";
my $end = "12/31/$year";

# get page 1 for a given day
my $ret = system("curl --silent --cookie-jar $cookie_root -H 'Accept: application/json' --output $json_dir/$json_root --dump-header $header '$osti\?entry_date_start=$start\&entry_date_end=$end'");
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
unlink($header);

# load page 1 with curl POST to Solr
$ret = system("docker exec -it my_solr post -c osti $json_in_client_dir/$json_root");
if ($ret) {
    die "curl POST of page 1 returned " . ($ret >> 8) . "\n";
}

# Only do the thread pool if there are more pages to process
# DEBUG
if (1 < $pages) {
    # make a pool of threads to load the remaining pages
    my @live_threads = ();
    for (my $t = 0; $t < $max_threads; $t++) {
        push(@live_threads, 
            threads->new(\&thread_main, $t, $max_threads, 
                $pages, $osti, $start, $end, $cookie_root, $json_dir, $json_root, $json_in_client_dir));
    }
    # wait for them to finish
    foreach my $thr (@live_threads) {
        $thr->join();
    }
}

# cleanup
chdir("/tmp");
unlink($cookie_root);
chdir($json_dir);
unlink($json_root);

### End of file
