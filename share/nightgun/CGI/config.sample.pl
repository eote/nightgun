#!/usr/bin/perl
use File::Spec;
our $DataDir = '/myplace/workspace/www/nightgun';
foreach my $dir (qw(. /myplace/workspace/www /myplace/www /var/www)) {
	my $n  = File::Spec->catdir($dir,'nightgun');
	if(-d $n) {
		$DataDir = $n;
		last;
	}
}
our $ConfigFile = "$DataDir/config.linux";

my $CGI;
foreach my $dir(qw(. /myplace/workspace/nightgun/share /usr/local/share	/usr/share )) {
	my $cgi = File::Spec->catfile($dir,'nightgun/CGI/nightgun.pl');
	if(-f $cgi) {
		$CGI = $cgi;
		last;
	}
}
die("No CGI script found\n") unless($CGI);
require $CGI;
