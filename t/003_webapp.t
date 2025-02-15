# -*- mode:perl -*-
use strict;
use warnings;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use t::Utils;
use Path::Class qw/ file dir /;

use_ok "pQuery";

my $app = setup_app;

test_psgi $app, sub {
    my $cb = shift;

    subtest index => sub {
        my $res = $cb->( GET "http://localhost/" );
        is $res->code, 200;
        like $res->content => qr{\A<\!DOCTYPE html>};
    };

    subtest notfound => sub {
        my $res = $cb->( POST "http://localhost/xxxxx" );
        is $res->code => 404, "not found xxxxx";
    };

    my $sid;
    my $next_uri;
    subtest start => sub {
        my $res = $cb->( GET "http://localhost/question" );

        is $res->code => 302, "status ok";
        $next_uri = $res->header("Location");
        like $next_uri => qr{^http://.*/question/.+$};

        $sid = res2sid($res);
        ok $sid;
   };

    my $page = 0;
    my $break;
 QUESTIONS:
    while (++$page <= 10) {
        my $choices;
        subtest question_get => sub {
            note "GET $next_uri";
            my $res = $cb->( GET $next_uri,
                             Cookie => "dojostate=$sid" );
            is $res->code => 200, "status 200";
            $sid = res2sid($res);

            my $pq = pQuery($res->content);
            is $pq->find(".counter strong")->html => $page, "counter $page";
            $choices = $pq->find(".choices")->length;
            note "choices=$choices";
        };

        subtest question_icon_get => sub {
            (my $uri = $next_uri) =~ s{/question/}{/question/icon/};
            my $res = $cb->( GET $uri,
                             Cookie => "dojostate=$sid" );
            is $res->code => 302, "status 302";
            like $res->header("Location") => qr{^https?://www\.gravatar\.com};
            note $res->header("Location");
            ok !$res->header("Set-Cookie");
        };

        subtest question_post_error => sub {
            note "POST $next_uri";
            my $res = $cb->( POST $next_uri,
                             Cookie  => "dojostate=$sid" );
            is $res->code => 200, "status 200";
            $sid = res2sid($res);

            my $pq = pQuery($res->content);
            ok $pq->find(".error")->html, "error message";
        };

        subtest question_post => sub {
            note "POST $next_uri";
            my $res = $cb->( POST $next_uri,
                             Cookie  => "dojostate=$sid",
                             Content => [ "choice" => int( rand($choices) ) + 1 ] );
            is $res->code => 200, "status 200";
            $sid = res2sid($res);

            my $pq = pQuery($res->content);
            is $pq->find(".counter strong")->html => $page, "counter $page";
            ok ! $pq->find(".error")->get(0), "no error message";
            my $node;
            if ( $node = $pq->find(".gotoNext")->get(0)
                      || $pq->find(".gotoResult")->get(0) )
            {
                ok $node;
                $next_uri = $node->getAttribute("href");
                ok $next_uri;
            }
            else {
                note $res->content;
                fail "no next uri";
                $break = 1;
            }
        };
        last QUESTIONS if $next_uri =~ /result/ || $break;
    } # end of QUESTIONS

    subtest result_get => sub {
        note "GET $next_uri";
        my $res = $cb->( GET $next_uri,
                         Cookie => "dojostate=$sid" );
        is $res->code => 200, "status 200";
        my $cookie = $res->header("Set-Cookie");
        like $cookie => qr{dojostate=;}, "delete cookie";
        like $cookie => qr{expires=[^;]+}, "delete cookie";

        my $pq = pQuery($res->content);
        for my $query (".blockResultHeader p", ".score", ".rank") {
            my $html = $pq->find($query)->html;
            ok $html;
            note $html;
        }

    };
};

done_testing;

sub res2sid {
    my $res    = shift;
    if ( $res->header("Set-Cookie") =~ m{dojostate=(.+?);} ) {
        ok $1;
        return $1;
    }
    return;
}
