package C4::Reserves2; #asummes C4/Reserves2

#requires DBI.pm to be installed
#uses DBD:Pg

use strict;
require Exporter;
use DBI;
use C4::Database;
#use C4::Accounts;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
  
# set the version for version checking
$VERSION = 0.01;
    
@ISA = qw(Exporter);
@EXPORT = qw(&FindReserves &CreateReserve);
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

sub FindReserves {
  my ($bib)=@_;
  my $dbh=C4Connect;
  my $query="Select * from reserves,borrowers where biblionumber=$bib and
reserves.borrowernumber=borrowers.borrowernumber";
  my $sth=$dbh->prepare($query);
  $sth->execute;
  my $i=0;
  my @results;
  while (my $data=$sth->fetchrow_hashref){
    $results[$i]=$data;
    $i++;
  }
  $sth->finish;
  $dbh->disconnect;
  return($i,\@results);
}

sub CreateReserve {                                                           
  my ($env,$branch,$borrnum,$biblionumber,$constraint,$bibitems,$priority) = @_;   
  my $fee=CalcReserveFee($env,$borrnum,$biblionumber,$constraint,$bibitems);
  my $dbh = &C4Connect;       
  my $const = lc substr($constraint,0,1);       
  my @datearr = localtime(time);                                
  my $resdate =(1900+$datearr[5])."-".($datearr[4]+1)."-".$datearr[3];                   
  #eval {                                                           
  # updates take place here             
  if ($fee > 0) {           
    my $nextacctno = &getnextacctno($env,$borrnum,$dbh);   
    my $updquery = "insert into accountlines       
    (borrowernumber,accountno,date,amount,description,accounttype,amountoutstanding)                                              
						          values
    ($borrnum,$nextacctno,now(),$fee,'Reserve Charge','Res',$fee)";          
    my $usth = $dbh->prepare($updquery);                      
    $usth->execute;             
    $usth->finish;                        
  }                     
  my $query="insert into reserves
  (borrowernumber,biblionumber,reservedate,branchcode,constrainttype,priority)           
  values ('$borrnum','$biblionumber','$resdate','$branch','$const','$priority')";   
  my $sth = $dbh->prepare($query);                        
  $sth->execute();                
  if (($const eq "o") || ($const eq "e")) {     
    my $numitems = @$bibitems;             
    my $i = 0;                                        
    while ($i < $numitems) {   
      my $biblioitem = @$bibitems[$i];   
      my $query = "insert into
      reserveconstraints                          
      (borrowernumber,biblionumber,reservedate,biblioitemnumber)         
      values
      ('$borrnum','$biblionumber','$resdate','$biblioitem')";                 
      my $sth = $dbh->prepare($query);                    
      $sth->execute();
      $sth->finish;
      $i++;                         
    }                                   
  } 
#  print $query;
  $dbh->disconnect();         
  return();   
}             

sub CalcReserveFee {
  my ($env,$borrnum,$biblionumber,$constraint,$bibitems) = @_;        
  #check for issues;    
  my $dbh = &C4Connect;           
  my $const = lc substr($constraint,0,1); 
  my $query = "select * from borrowers,categories 
  where (borrowernumber = '$borrnum')         
  and (borrowers.categorycode = categories.categorycode)";   
  my $sth = $dbh->prepare($query);                       
  $sth->execute;                                    
  my $data = $sth->fetchrow_hashref;                  
  $sth->finish();       
  my $fee = $data->{'reservefee'};         
  my $cntitems = @->$bibitems;   
  if ($fee > 0) {                         
    # check for items on issue      
    # first find biblioitem records       
    my @biblioitems;    
    my $query1 = "select * from biblio,biblioitems                           
    where (biblio.biblionumber = '$biblionumber')     
    and (biblio.biblionumber = biblioitems.biblionumber)";
    my $sth1 = $dbh->prepare($query1);                   
    $sth1->execute();                                     
    while (my $data1=$sth1->fetchrow_hashref) { 
      if ($const eq "a") {    
        push @biblioitems,$data1;       
      } else {                     
        my $found = 0;        
	my $x = 0;
	while ($x < $cntitems) {                                             
          if (@$bibitems->{'biblioitemnumber'} == $data->{'biblioitemnumber'}) {         
            $found = 1;   
	  }               
	  $x++;                                       
	}               
	if ($const eq 'o') {if ($found == 1) {push @biblioitems,$data;}                            
        } else {if ($found == 0) {push @biblioitems,$data;} }     
      }   
    }             
    $sth1->finish;                                  
    my $cntitemsfound = @biblioitems; 
    my $issues = 0;                 
    my $x = 0;                   
    my $allissued = 1; 
    while ($x < $cntitemsfound) { 
      my $bitdata = @biblioitems[$x];                                       
      my $query2 = "select * from items                   
      where biblioitemnumber = '$bitdata->{'biblioitemnumber'}'";     
      my $sth2 = $dbh->prepare($query2);                       
      $sth2->execute;   
      while (my $itdata=$sth2->fetchrow_hashref) { 
        my $query3 = "select * from issues
        where itemnumber = '$itdata->{'itemnumber'}' and
        returndate is null";                                                          
        my $sth3 = $dbh->prepare($query3);                      
        $sth3->execute();                     
        if (my $isdata=$sth3->fetchrow_hashref) { } else
        {$allissued = 0; }  
      }                                                           
      $x++;   
    }         
    if ($allissued == 0) { 
      my $rquery = "select * from reserves           
      where biblionumber = '$biblionumber'"; 
      my $rsth = $dbh->prepare($rquery);   
      $rsth->execute();   
      if (my $rdata = $rsth->fetchrow_hashref) { } else {                                     
        $fee = 0;                                                           
      }   
    }             
  }                   
  $dbh->disconnect();   
  return $fee;                                      
}                   

sub getnextacctno {                                                           
  my ($env,$bornumber,$dbh)=@_;           
  my $nextaccntno = 1;      
  my $query = "select * from accountlines                             
  where (borrowernumber = '$bornumber')                               
  order by accountno desc";                       
  my $sth = $dbh->prepare($query);                                  
  $sth->execute;                    
  if (my $accdata=$sth->fetchrow_hashref){    
    $nextaccntno = $accdata->{'accountno'} + 1;           
  }                       
  $sth->finish;                                       
  return($nextaccntno);                   
}              








			
END { }       # module clean-up code here (global destructor)
