#!/usr/bin/perl -w
use strict;
use FileHandle;

# for each day of the last year
# curl the first page of osti entries, find the number of total pages
# from header and multiply pages * bytes to estimate volume.
#
# Note: I know this overestimates pages by .5 on average
# and using the first page size may also be questionable

my $now = time();
my $then = $now - (16 * 365 * 24 * 3600);
my $total = 0;
while ($now > $then) {
    # format the day as MM/DD/YY and
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($now);
    my $start = sprintf("01/01/%04d", $year+1900);
    my $end = sprintf("12/31/%04d", $year+1900);
    
    # get page 1 for a given day
    my $ret = system("curl --silent --cookie-jar cookie.jar -H 'Accept: application/json' --output records.json --dump-header records.headers 'https://www.osti.gov/api/v1/records\?entry_date_start=$start\&entry_date_end=$end'");
    if ($ret) {
        die "curl returned " . ($ret >> 8) . "\n";
    }

    # get the number of pages of records for that day from the headers
    my $fh = FileHandle->new("<records.headers") || die "can't read records.headers: $!\n";
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
    #    die "headers didn't contain Link header\n" if (0 == $pages);

    # get the size of 20 records for that day from the json output
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
        $atime,$mtime,$ctime,$blksize,$blocks) = stat('records.json');

    # If there are no entries for a day, then there will be no Link header with a last
    # page but json will also be an empty array
    die "size is $size" if ((2 < $size) && (0 == $pages));

    if (($pages > 0) && ($size > 0)) {
        my $mb = ($pages * $size)/(1024*1024);
        print "$start $pages $size = " . int($mb) . " MB\n";    
        $total += $mb;
    }
    else {
        print "$start 0 0 = 0 MB\n";
    }

    # do the previous day
    $now -= 365 * 24 * 3600;
}
print "TOTAL " . int($total) . "\n";

# End of file
