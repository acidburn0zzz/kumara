package C4::Circulation; #asummes C4/Circulation

#package to deal with circulation 

use strict;
require Exporter;
use DBI;
use C4::Database;
use C4::Circulation::Issues;
use C4::Interface;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
  
# set the version for version checking
$VERSION = 0.01;
    
@ISA = qw(Exporter);
@EXPORT = qw(&Start_circ);
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

sub Start_circ{
  my ($env)=@_;
  #connect to database
  #start interface
  &startint($env,'Circulation');
  my ($reason,$data)=menu('console','Circulation',('Issues','Returns','Borrower Enquiries'));
  my $donext;
  if ($data eq 'Issues'){  
    $donext=Issue($env);
  } else {
    &endint($env);
  }
  if ($donext eq 'Circ'){
    Start_circ($env);
  } else {
    &endint($env);
  }
}

sub pastitems{
  #Get list of all items borrower has currently on issue
  my ($env,$bornum,$dbh)=@_;
  my $sth=$dbh->prepare("Select * from issues,items,biblio
  where borrowernumber=$bornum and issues.itemnumber=items.itemnumber
  and items.biblionumber=biblio.biblionumber");
  $sth->execute;
  my $i=0;
  my @items;
  while (my $data=$sth->fetchrow_hashref){
     $items[$i]="$data->{'title'} $data->{'date_due'}";    
     $i++;
  }
  return(\@items);
}

sub checkoverdues{
  #checks whether a borrower has overdue items
  my ($env,$bornum,$dbh)=@_;
  my $sth=$dbh->prepare("Select * from issues,items,biblio where
  borrowernumber=$bornum and issues.itemnumber=items.itemnumber and
  items.biblionumber=biblio.biblionumber");
  $sth->execute;
  my $row=1;
  my $col=40;
  while (my $data=$sth->fetchrow_hashref){
    output($row,$col,$data->{'title'});
    $row++;
  }
  $sth->finish;
}

sub previousissue {
  my ($env,$itemnum,$dbh,$bornum)=@_;
  my $sth=$dbh->prepare("Select firstname,surname,issues.borrowernumber,cardnumber
  from issues,borrowers where 
  issues.itemnumber='$itemnum' and
  issues.borrowernumber=borrowers.borrowernumber");
  $sth->execute;
  my $borrower=$sth->fetchrow_hashref;
  $sth->finish;
  if ($borrower->{'borrowernumber'} ne ''){
    if ($bornum eq $borrower->{'borrowernumber'}){
      output(1,24,"Book is marked as issue to current borrower");       
      #  my $resp = &msg_yn("Book is marked as issue to current borrower");
  
    } else {
      my $text="Issued to $borrower->{'firstname'} $borrower->{'surname'} ($borrower->{'cardnumber'})";    
      output(1,24,$text);
      # my $resp = &msg_yn($text);
    }
  } 
  return($borrower->{'borrowernumber'});
}


sub checkreserve{
  # Check for reserves for biblio 
  # does not look at constraints yet
  my ($env,$dbh,$itemnum)=@_;
  my $resbor = "";
  my $query = "select * from reserves,items 
  where (items.itemnumber = '$itemnum')
  and (items.biblionumber = reserves.biblionumber)
  and (reserves.found is null) order by priority";
#  print $query;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  if (my $data=$sth->fetchrow_hashref) {
    $resbor = $data->{'borrowernumber'}; 
  }
  return ($resbor);
}

sub checkwaiting{
  # check for reserves waiting
  my ($env,$dbh,$bornum)=@_;
  my @itemswaiting="";
  my $query = "select * from reserves
  where (borrowernumber = '$bornum')
  and (reserves.found='W')";
  if ($env->{'debug'} > 4) {
    output(1,20,$query);
  }
  my $sth = $dbh->prepare($query);
  $sth->execute();
  if (my $data=$sth->fetchrow_hashref) {
    push @itemswaiting,$data->{'itemnumber'}; 
  }
  return (\@itemswaiting);
}

sub scanbook {
  my ($env,$interface)=@_;
  #scan barcode
#  my $number='L01781778';  
  my ($number,$reason)=dialog("Book Barcode:");
  $number=uc $number;
  return ($number,$reason);
}

sub scanborrower {
  my ($env,$interface)=@_;
  #scan barcode
# my $number='V00126643';  
  my ($number,$reason)=&Borr_dialog($env);
  $number=uc $number;
  return ($number,$reason);
}


END { }       # module clean-up code here (global destructor)
