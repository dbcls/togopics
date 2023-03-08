#!/usr/bin/env perl

=head
Given a list of illustration file names, this script makes a link to its corresponding WikimediaCommons entry
from a Wikidata entry to which the WikimediaCommons one points using P180 ("depicts").

Prerequisites:
There is already a link from a WikimediaCommons entry to a Wikidata one with the property of P180.

Yasunori Yamamoto @ Database Center for Life Science

このファイルはUTF-8エンコードされた文字を含みます。
=cut

use strict;
use warnings;
use Fatal qw/open/;
use utf8; 
use LWP::UserAgent;
use LWP::Protocol::https;
use Encode;
use Term::ReadKey;
use HTTP::Request::Common;
use JSON::XS;
use Data::Dumper;
use Time::HiRes q/sleep/;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $browser;
my $ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:22.0) Gecko/20100101 Firefox/22.0";
my $wb_api_url = "https://commons.wikimedia.org/w/api.php";
my $wd_api_url = "https://www.wikidata.org/w/api.php";
my $author = "DataBase Center for Life Science (DBCLS)";
my $pictures = "pictures.tsv";

&main;

sub getAccountInfo {
    my ($username, $password);
    print "Enter your username: ";
    $username = <STDIN>;
    print "Enter your password: ";
    ReadMode('noecho');
    $password = ReadLine(0);
    ReadMode('normal');
    chomp ($username, $password);
    print "\n";
    return [$username, $password];
}

sub initBrowser {
    $browser = LWP::UserAgent->new( agent => $ua );
    $browser->default_header( 'Accept-Language' => 'en-US' );
    $browser->default_header( 'Accept-Charset' => 'iso-8859-1,*,utf-8' );
    $browser->default_header( 'Accept' => '*/*' );
    $browser->cookie_jar( {} );
}

sub loginAndGetToken {
    my $userinfo = &getAccountInfo;
    my $token = "";
    my $response = $browser->post(
	    $wd_api_url,
	    Content_Type => "application/x-www-form-urlencoded",
	    Content_Encoding => "utf-8",
	    Content => [
	        "action"     => "login",
	        "lgname"     => $userinfo->[0],
	        "lgpassword" => $userinfo->[1],
	        "format"     => "json",
	    ]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
        $token = $res_ref->{"login"}->{"token"};
    }else{
	    die "Post error: $!\n";
    }

    $response = $browser->post(
	    $wd_api_url,
	    Content_Type => "application/x-www-form-urlencoded",
	    Content_Encoding => "utf-8",
	    Content=> [
	        "action"     => "login",
	        "lgname"     => $userinfo->[0],
	        "lgpassword" => $userinfo->[1],
	        "lgtoken"    => $token,
	        "format"     => "json",
	    ]);
    if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    if( $res_ref->{"login"}->{"result"} eq "Success" ){
	        print "lguserid:", $res_ref->{"login"}->{"lguserid"}, "\n";
	        print "lgusername:", $res_ref->{"login"}->{"lgusername"}, "\n";
	    }else{
	        open(my $debug, ">", "debug.txt");
	        print $debug $response->as_string;
	        close($debug);
	        die "Failed to login. Please check the file 'debug.txt'.\n";
	    }
    }else{
	    die "Post error: $!\n";
    }

    my $url = URI->new( $wd_api_url );
    $url->query_form(
	    "action" => "query",
	    "meta"   => "tokens",
	    "format" => "json",
	);
    $response = $browser->get( $url );
    if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    return $res_ref->{"query"}->{"tokens"}->{"csrftoken"};
    }else{
	    die "Get error: $!\n";
    }
}

sub getWbEntityID {
    my $fn = shift;
    $fn = "File:".$fn;
    my $url = URI->new( $wb_api_url );
    $url->query_form(
        "action" => "wbgetentities",
        "sites"  => "commonswiki",
        "titles" => $fn, # eg "File:201703_tardigrade.svg"
        "format" => "json",
	);
    my $response = $browser->get( $url );
    if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    my $eid = [ keys %{$res_ref->{"entities"}} ]->[0];
	    return $eid;
    }else{
	    return "";
    }
}

# https://commons.wikimedia.org/w/api.php?action=wbgetclaims&entity=M57116616
sub getWbClaims {
    my $eid = shift;
    my $url = URI->new( $wb_api_url );
    $url->query_form(
	    "action" => "wbgetclaims",
	    "entity" => $eid,
	    "format" => "json",
	);
    my $response = $browser->get( $url );
    if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    if( my $claims = $res_ref->{'claims'} ){
            return $claims;
	    }elsif( defined($res_ref->{'error'}) ){
            return "";
        }
    }else{
        return "";
    }
}

sub getWbDepictsClaims {
    my $eid = shift;
    my $pid = "P180";
    my $claims = getWbClaims( $eid );
    my @qids = ();
    if( $claims eq "" ){
        return \@qids;
    }
    while(my ($k, $v) = each %$claims){
        next if $k ne $pid;
        for my $value ( @{ $claims->{$k} } ){
            push @qids, $value->{'mainsnak'}->{'datavalue'}->{'value'}->{'id'};
        }
    }
    return \@qids;
}

sub existWbClaim {
    my $eid = shift;
    my $pid = shift;
    my $qid = shift;
    my $claims = getWbClaims($eid);
    while(my ($k, $v) = each %$claims){
	    next if $k ne $pid;
	    for my $value ( @{ $claims->{$k} } ){
	        if( $value->{'mainsnak'}->{'datavalue'}->{'value'}->{'id'} eq $qid ){
		        return 1;
	        }
	    }
    }
    return 0;
}

sub setWbClaims {
    my $eid = shift;
    my $qid = shift;
    my $edit_token = shift;
    if( existClaim($eid, "P180", $qid) > 0 ){
	    print "Already stated: ", join("\t", ($eid, "P180", $qid)), "\n";
	    return;
    }
    $qid =~ s/^Q//;
    my $value = encode_json {
	    "entity-type" => "item",
	    "numeric-id" => $qid,
	    "id" => "Q${qid}"
    };
    my $url = URI->new( $wb_api_url );
    my $response = $browser->post(
	    $url,
	    Content_Type     => "multipart/form-data",
	    Content_Encoding => "utf-8",
	    Content => [
	        "action"   => "wbcreateclaim",
	        "entity"   => $eid,
	        "property" => "P180",
	        "snaktype" => "value",
	        "value"    => $value,
	        "summary"  => "Added structured data.",
	        "token"    => $edit_token,
	        "format"   => "json",
	    ]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	    if( $res_ref->{'success'} ){
	        print "setClaims [${eid}]: Q${qid}\n";
	    }elsif( defined($res_ref->{'error'}) ){
	        print "Error [$eid]: ", $res_ref->{'error'}->{'info'}, "\n";
	    }else{
	        print Dumper $res_ref, "\n";
	    }
    }else{
	    die "Post error: $!\n";
    }
}

sub setWbLabel {
    my $title = shift;
    my $label = shift;
    my $lang = shift;
    my $edit_token = shift;
    my $url = URI->new( $wb_api_url );
    my $response = $browser->post(
	    $url,
	    Content_Type     => "multipart/form-data",
	    Content_Encoding => "utf-8",
	    Content => [
	        "action"   => "wbsetlabel",
	        "site"     => "commonswiki",
	        "title"    => "File:".$title,
	        "value"    => $label,
	        "language" => $lang,
	        "summary"  => "Added a label (".$lang.").",
	        "token"    => $edit_token,
	        "format"   => "json",
	    ]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	    print "setLabel:",decode_utf8($label), "\n";
    }else{
	    die "Post error: $!\n";
    }
}

# https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=Q25851&property=P18
sub getWdClaims {
    my $qid = shift;
    my $property = shift; # "P18"
    my $url = URI->new( $wd_api_url );
    $url->query_form(
	    "action" => "wbgetclaims",
	    "entity" => $qid,
        "property" => $property,
	    "format" => "json",
	);
    my $response = $browser->get( $url );
    if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    if( my $claims = $res_ref->{'claims'}->{$property} ){
            # ptr to array : [{"mainsnak":{"snaktype": "value",,,},"datatype": "commonsMedia"},...]
            return $claims;
	    }elsif( defined($res_ref->{'error'}) ){
            return "";
        }
    }else{
        return "";
    }
}

sub existWdClaim {
    my $qid = shift;
    my $filename = shift; # e.g., "202111 Asiatic hard clam.svg"
    my $claims = getWdClaims($qid, "P18");
    for my $c ( @$claims ){
        if( $c->{'mainsnak'}->{'datavalue'}->{'value'} eq $filename ){
            return 1;
        }
    }
    return 0;
}

# action=wbsetqualifier&claim=Q4115189$4554c0f4-47b2-1cd9-2db9-aa270064c9f3&property=P1&value="GdyjxP8I6XB3"&snaktype=value&token=foobar
sub setWdQualifier {
    my $cid = shift;
    # P275: 利用許諾 (Q20007257: CC BY 4.0 International)
    # "value": {
    #    "entity-type": "item",
    #    "numeric-id": 20007257,
    #    "id": "Q20007257"
    #},
    # P2096: キャプション ("Illustration of Rhesus monkey")
    # "value": {
    #    "text": "Illustration of Rhesus monkey",
    #    "language": "en"
    # }
    my $property = shift;
    my $value = shift;
    my $edit_token = shift;
    my $url = URI->new( $wd_api_url );
    my $response = $browser->post(
        $url,
        Content_Type     => "multipart/form-data",
        Content_Encoding => "utf-8",
        Content => [
            "action"   => "wbsetqualifier",
            "claim"    => $cid,
            "property" => $property,
            "snaktype" => "value",
            "value"    => $value,
            "token"    => $edit_token,
            "format"   => "json",
        ]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	    if( $res_ref->{'success'} ){
	        print "setQualifier [${cid}]->[${property}]: ${value}\n";
	    }elsif( defined($res_ref->{'error'}) ){
	        print "Error [$cid]: ", $res_ref->{'error'}->{'info'}, "\n";
	    }else{
	        print Dumper $res_ref, "\n";
	    }
    }else{
	    die "Post error: $!\n";
    }
}

# action=wbcreateclaim&entity=Q25851&property=P18&snaktype=value&value="\"202111 Asiatic hard clam.svg\""
sub setWdClaim {
    my $qid = shift;
    my $filename = shift; # e.g., "202111 Asiatic hard clam.svg"
    my $edit_token = shift;
    if( existWdClaim( $qid, $filename ) > 0){
	    print "Already stated: ", join("\t", ($qid, $filename)), "\n";
	    return;
    }
    my $vfn = q(").$filename.q(");
    print $vfn, "\n";
=head
{
	"action": "wbcreateclaim",
	"format": "json",
	"entity": "Q_____",
	"snaktype": "value",
	"property": "P18",
	"value": "\"202111 Asiatic hard clam.svg\"",
	"token": "+\\",
	"formatversion": "2"
}
=cut
    my $url = URI->new( $wd_api_url );
    my $response = $browser->post(
	    $url,
	    Content_Type     => "multipart/form-data",
	    Content_Encoding => "utf-8",
	    Content => [
            "action"   => "wbcreateclaim",
	        "entity"   => $qid,
	        "property" => "P18",
	        "snaktype" => "value",
	        "value"    => $vfn,
	        "summary"  => "Added image data.",
	        "token"    => $edit_token,
	        "format"   => "json",
            "formatversion" => "2"
	    ]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	    if ( $res_ref->{'success'} ){
	        print "setClaims [${qid}]->[P18] (", $res_ref->{'claim'}->{'id'}, "): ${filename}\n";
            my $cid = $res_ref->{'claim'}->{'id'};
            my $value = encode_json {
                "entity-type" => "item",
                "numeric-id"  => 20007257,
                "id"          => "Q20007257"
            };
            setWdQualifier( $cid, "P275", $value, $edit_token );
            (my $caption_string = $filename) =~ s/\.svg$//;
            $caption_string =~ s/^\d+ //;
            $value = encode_json {
                "text"     => "Illustration of ${caption_string}.",
                "language" => "en"
            };
            setWdQualifier( $cid, "P2096", $value, $edit_token );
	    }elsif( defined($res_ref->{'error'}) ){
	        print "Error [$qid]: ", $res_ref->{'error'}->{'info'}, "\n";
	    }else{
	        print Dumper $res_ref, "\n";
	    }
        return "";
    }else{
	    die "Post error: $!\n";
    }
}

sub getFiles {
    open(my $fh, $pictures);
    while(<$fh>){
        chomp;
        my ($tax_id, $filename) = split /\t/;
        next if $tax_id !~ /^\d+$/;
        next if $filename !~ /^\d+_/;
        next if $tax_id eq "9606";
        my $eid = getWbEntityID( $filename );
        my $claims = [];
        if( $eid ){
            $claims = getWbDepictsClaims( $eid );
        }
        print join("\t", ($tax_id, $filename, $eid, join(",", @$claims))), "\n";
#        $filename =~ tr/_/ /;
#        for my $c ( @$claims ){
#            my $links = getWdClaims($c, "P18");
#            print join("\n", map { " ". $_->{'id'}. ":". $_->{'mainsnak'}->{'datavalue'}->{'value'} } @$links), "\n";
#        }
        sleep 0.4;
    }
    close($fh);
}

sub main {

    &initBrowser;
    &getFiles();
#    my $edit_token = &loginAndGetToken;
#    setWdClaim("Q938020", "201611 melitaea cinxia sacarina.svg", $edit_token);

}

__END__