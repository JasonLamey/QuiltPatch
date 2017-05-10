requires "Dancer2" => "0.203001";

recommends "YAML"             => "0";
recommends "URL::Encode::XS"  => "0";
recommends "CGI::Deurl::XS"   => "0";
recommends "HTTP::Parser::XS" => "0";

requires   "DBI"                      => "1.636";
requires   "DBD::mysql"               => "4.042";
requires   "DBIx::Class"              => "0.082840";
requires   "Const::Fast"              => "0.014";
requires   "DateTime"                 => "1.42";
requires   "URI::Escape::JavaScript"    => "0.04";

on "test" => sub {
    requires "Test::More"            => "0";
    requires "HTTP::Request::Common" => "0";
};
