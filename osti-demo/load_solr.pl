#!/usr/bin/perl -w
use strict;
use FileHandle;
use Getopt::Long;
use threads;
use HTTP::Request;
use JSON::XS;
use Apache::Solr;
use Apache::Solr::JSON;

### Configuration
my $osti = "https://www.osti.gov/api/v1/records";
my $solr = "http://localhost:8983/solr/osti";

### Globals

### Subroutines
sub usage($) {
    my ($msg) = @_;
    die "usage: $0 threads rows start end\n$msg\n";
}

sub get_osti($$$) {
    my ($page, $read_url, $write_url) = @_;
    for (my $j = 1; $j <= 5; $j++) {
        my $ua = LWP::UserAgent->new();
        # FIXME what about cookies?
        my $request = HTTP::Request->new(
                'GET', 
                $read_url,
            );
        $request->header('Accept', 'application/json');
        my $response = $ua->request($request);
        if ($response->is_success()) {
            my $link = $response->header('Link');
            # if there was any data, then HATEOS returns Links in header
            if ($link) {
                # Solar handle
                my $sh = Apache::Solr::JSON->new(server => $write_url);
                # String converted to json array
                my $body = decode_json($response->decoded_content());
                my @docs = ();
                foreach my $obj (@$body) {
                    my $doc = Apache::Solr::Document->new();
                    foreach my $field (keys(%$obj)) {
                        $doc->addField($field => $obj->{$field});
                    }
                    push(@docs, $doc);
                }
                my $results = $sh->addDocument(\@docs);
                $results or die("Failed to add to Solr $solr " . $results->errors() . "\n");
            }
            return $response->header('Link');
        }
        else {
            warn("Request of page $page returned " . $response->status_line() . " sleeping $j squared\n");
            sleep($j*$j);
        }
    }
    die "Request failed after 5 tries\n";
}

sub thread_main($$$$$$$$$$) {
    my ($thread_number, $total_threads, $rows, $pages, $osti, $start, $end, $cookie, $json_dir, $json_root, $json_in_client_dir) = @_;

    # get the rest of the pages
    my $body;
    for (my $i = $thread_number+1; $i <= $pages; $i += $total_threads) {
        next if (1 == $i); # first page already handled before starting threads

        print("\n\nWorking on page $i of $pages\n\n");
    
        # ignoring the Link header
        get_osti(
                $i,
                "$osti\?entry_date_start=$start\&entry_date_end=$end\&page=$i\&rows=$rows",
                $solr
            );
    }
}

### Main

# set up the defaults
my $max_threads = 8; # best guess
my $rows = 3000; # this seems to be the maximum
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
my $start = sprintf("%02d/%02d/%04d", $mon+1, $mday, $year+1900);
my $end = $start; # Default to loading just today
    
# Override defaults from command line
GetOptions("threads=i" => \$max_threads,    # numeric
            "rows=i"   => \$rows,      # string
            "start=s"  => \$start,
            "end=s"  => \$end
        ) or usage("Error in command line arguments");

# Do some additional command-line validation first
if ($start !~ m#^\d\d/\d\d/\d\d\d\d$#) {
    usage("start date should be in MM/DD/YYYY format");
}
if ($end !~ m#^\d\d/\d\d/\d\d\d\d$#) {
    usage("end date should be in MM/DD/YYYY format");
}

print("Running with $max_threads threads $rows $rows from $start to $end inclusive\n");

# get page 1 for a given day
my $header = get_osti(
                1,
                "$osti\?rows=3000\&entry_date_start=$start\&entry_date_end=$end",
                $solr);

# Links are a comma separated list
my $pages = 0;
foreach my $link (split(/,/, $header)) {
    # and we want the one that lets us access the last page
    if ($link=~ m/; rel="last"/) { 
        if ($link =~ m/[?&]page=(\d+)[&>]/) {
            $pages = $1;
        }
    }
}
# if we see a Link header but it has no values, that's 1 page
$pages = 1 if (0 == $pages);

# Only do the thread pool if there are more pages to process
if (1 < $pages) {
    # make a pool of threads to load the remaining pages
    my @live_threads = ();
    for (my $t = 0; $t < $max_threads; $t++) {
        push(@live_threads, 
            threads->new(\&thread_main, $t, $max_threads, $rows,
                $pages, $osti, $start, $end));
    }
    # wait for them to finish
    foreach my $thr (@live_threads) {
        $thr->join();
    }
}

### End of file
