package C4::Search; #asummes C4/Search

#requires DBI.pm to be installed
#uses DBD:Pg

use strict;
require Exporter;
use DBI;
use C4::Database;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
  
# set the version for version checking
$VERSION = 0.01;
    
@ISA = qw(Exporter);
@EXPORT = qw(&CatSearch);
%EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
		  
# your exported package globals go here,
# as well as any optionally exported functions

@EXPORT_OK   = qw($Var1 %Hashit);


# non-exported package globals go here
use vars qw(@more $stuff);
	
# initalize package globals, first exported ones

my $Var1   = '';
my %Hashit = ();
		    
# then the others (which are still accessible as $Some::Module::stuff)
my $stuff  = '';
my @more   = ();
	
# all file-scoped lexicals must be created before
# the functions below that use them.
		
# file-private lexicals go here
my $priv_var    = '';
my %secret_hash = ();
			    
# here's a file-private function as a closure,
# callable as &$priv_func;  it cannot be prototyped.
my $priv_func = sub {
  # stuff goes here.
};
						    
# make all your functions, whether exported or not;



sub CatSearch  {
  my ($searchstring,$type)=@_;
  my $dbh = &C4Connect;
  my $query="Select * from biblio where $type like '%$searchstring%'";
  print $query,"\n";
  my $sth=$dbh->prepare($query);
  $sth->execute;
  while (my @data=$sth->fetchrow_array){
    print @data,"\n";
  }
  $sth->execute;
  $sth->finish;
  $dbh->disconnect;
  
}    
			
END { }       # module clean-up code here (global destructor)
