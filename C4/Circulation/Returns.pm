package C4::Circulation::Returns; #assumes C4/Circulation/Returns

#package to deal with Returns
#written 3/11/99 by olwen@katipo.co.nz

use strict;
require Exporter;
use DBI;
use C4::Database;
use C4::Accounts;
use C4::InterfaceCDK;
use C4::Circulation::Main;
use C4::Format;
use C4::Scan;
use C4::Stats;
use C4::Search;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
  
# set the version for version checking
$VERSION = 0.01;
    
@ISA = qw(Exporter);
@EXPORT = qw(&returnrecord &calc_odues &Returns);
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

sub Returns {
  my ($env)=@_;
  my $dbh=&C4Connect;  
  my @items;
  @items[0]=" "x50;
  my $reason;
  my $item;
  my $reason;
  my $borrower;
  my $itemno;
  my $itemrec;
  my $bornum;
  my $amt_owing;
  my $odues;
# until (($reason eq "Circ") || ($reason eq "Quit")) {
  until ($reason ne "") {
    ($reason,$item) =  
      returnwindow($env,"Enter Returns",
      $item,\@items,$borrower,$amt_owing,$odues,$dbh); #C4::Circulation
    #debug_msg($env,"item = $item");
    #if (($reason ne "Circ") && ($reason ne "Quit")) {
    if ($reason eq "")  {
      my $resp;
      ($resp,$bornum,$borrower,$itemno,$itemrec,$amt_owing) = checkissue($env,$dbh,$item);
      if ($resp ne "") {
        if ($resp eq "Returned") {
	  my $item = itemnodata($env,$dbh,$itemno);
	  #my $fmtitem = fmtstr($env,$itemrec->{'title'},"L50");
      	  my $fmtitem = C4::Circulation::Issues::formatitem($env,$item,"",$amt_owing);
	  unshift @items,$fmtitem;     	  
  	} elsif ($resp ne "") {
	  error_msg($env,"$resp");
	}
      }
    }
  }
  clearscreen;
  $dbh->disconnect;
  return($reason);
  }
  
sub checkissue {
  my ($env,$dbh, $item) = @_;
  my $reason='Circ';
  my $bornum;
  my $borrower;
  my $itemno;
  my $itemrec;
  my $amt_owing;
  $item = uc $item;
  my $query = "select * from items,biblio 
    where barcode = '$item'
    and (biblio.biblionumber=items.biblionumber)";
  my $sth=$dbh->prepare($query); 
  $sth->execute;
  if ($itemrec=$sth->fetchrow_hashref) {
     $sth->finish;
     $query = "select * from issues
       where (itemnumber='$itemrec->{'itemnumber'}')
       and (returndate is null)";
     my $sth=$dbh->prepare($query);
     $sth->execute;
     if (my $issuerec=$sth->fetchrow_hashref) {
       $sth->finish;
       $query = "select * from borrowers where
       (borrowernumber = '$issuerec->{'borrowernumber'}')";
       my $sth= $dbh->prepare($query);
       $sth->execute;
       $env->{'bornum'}=$issuerec->{'borrowernumber'};
       $borrower = $sth->fetchrow_hashref;
       $bornum = $issuerec->{'borrowernumber'};
       $itemno = $issuerec->{'itemnumber'};
       $amt_owing = returnrecord($env,$dbh,$bornum,$itemno);     
       $reason = "Returned";    
     } else {
       $sth->finish;
       $reason = "Item not issued";
     }
     my ($resfound,$issrec) = find_reserves($env,$dbh,$itemrec->{'itemnumber'});
     if ($resfound eq "y") {
       my $mess = "Reserved for collection at branch $issrec->{'branchcode'}"; 
       error_msg($env,$mess);
     }  
   } else {
     $sth->finish;
     $reason = "Item not found";
  }   
  return ($reason,$bornum,$borrower,$itemno,$itemrec,$amt_owing);
  # end checkissue
  }
  
sub returnrecord {
  # mark items as returned
  my ($env,$dbh,$bornum,$itemno)=@_;
  #my $amt_owing = calc_odues($env,$dbh,$bornum,$itemno);
  my @datearr = localtime(time);
  my $dateret = (1900+$datearr[5])."-".$datearr[4]."-".$datearr[3];
  my $query = "update issues set returndate = '$dateret', branchcode ='$env->{'branchcode'}' where 
    (borrowernumber = '$bornum') and (itemnumber = '$itemno') 
    and (returndate is null)";  
  my $sth = $dbh->prepare($query);
  $sth->execute;
  $sth->finish;
  # check for overdue fine
  my $oduecharge;
  my $query = "select * from accountlines
    where (borrowernumber = '$bornum')
    and (itemnumber = '$itemno')
    and (accounttype = 'F')";
  my $sth = $dbh->prepare($query);
    $sth->execute;
    if (my $data = $sth->fetchrow_hashref) {
       # alter fine to show that the book has been returned.
       my $uquery = "update accountlines
         set accounttype = 'FR'
         where (borrowernumber = '$bornum')
         and (itemnumber = '$itemno')
         and (accountno = '$data->{'accountno'}') ";
       my $usth = $dbh->prepare($uquery);
       $usth->execute();
       $usth->finish();
       $oduecharge = $data->{'amountoutstanding'};
    }
    $sth->finish;
  # check for charge made for lost book
  my $query = "select * from accountlines 
    where (borrowernumber = '$bornum') 
    and (itemnumber = '$itemno')
    and (accounttype = 'L')";
  my $sth = $dbh->prepare($query);
  $sth->execute;
  if (my $data = $sth->fetchrow_hashref) {
    # writeoff this amount 
    my $offset;
    my $amount = $data->{'amount'};
    my $acctno = $data->{'accountno'};
    my $amountleft;
    if ($data->{'amountoutstanding'} == $amount) {
       $offset = $data->{'amount'};
       $amountleft = 0;
    } else {
       $offset = $amount - $data->{'amountoutstanding'};
       $amountleft = $data->{'amountoutstanding'} - $amount;
    }
    my $uquery = "update accountlines
      set accounttype = 'LR',amountoutstanding='0'
      where (borrowernumber = '$bornum')
      and (itemnumber = '$itemno')
      and (accountno = '$acctno') ";
    my $usth = $dbh->prepare($uquery);
    $usth->execute();
    $usth->finish;
    my $nextaccntno = getnextacctno($env,$bornum,$dbh);
    $uquery = "insert into accountlines
      (borrowernumber,accountno,date,amount,description,accounttype,amountoutstanding)
      values ($bornum,$nextaccntno,now(),0-$amount,'Book Returned',
      'CR',$amountleft)";
    $usth = $dbh->prepare($uquery);
    $usth->execute;
    $usth->finish;
    $uquery = "insert into accountoffsets
      (borrowernumber, accountno, offsetaccount,  offsetamount)
      values ($bornum,$data->{'accountno'},$nextaccntno,$offset)";
    $usth = $dbh->prepare($uquery);
    $usth->execute;
    $usth->finish;
  } 
  $sth->finish;
  UpdateStats($env,'branch','return','0');
  return($oduecharge);
}

sub calc_odues {
  # calculate overdue fees
  my ($env,$dbh,$bornum,$itemno)=@_;
  my $amt_owing;
  return($amt_owing);
}  

sub find_reserves {
  my ($env,$dbh,$itemno) = @_;
  my $itemdata = itemnodata($env,$dbh,$itemno);
  my $query = "select * from reserves where found is null 
  and biblionumber = $itemdata->{'biblionumber'} order by priority,reservedate ";
  my $sth = $dbh->prepare($query);
  $sth->execute;
  my $resfound = "n";
  my $resrec;
  while (($resrec=$sth->fetchrow_hashref) && ($resfound eq "n")) {
    if ($resrec->{'constrainttype'} eq "a") {
      $resfound = "y";
    } else {
      my $conquery = "select * from reserveconstraints
        where borrowernumber = $resrec->{'borrowernumber'}
	and reservedate = $resrec->{'reservedate'}
	and biblionumber = $resrec->{'biblionumber'}
	and biblioitemnumber = $itemdata->{'biblioitemnumber'}";
      my $consth = $dbh->prepare($conquery);
      $consth->execute;
      if (my $conrec=$consth->fetchrow_hashref) {
        if ($resrec->{'constrainttype'} eq "o") {
	   $resfound = "y";
	 }
      } else {
        if ($resrec->{'constrainttype'} eq "e") {
	  $resfound = "y";
	}
      }
      $consth->finish;
    }
    if ($resfound = "y") {
      my $updquery = "update reserves set found = 'W'
        where borrowernumber = $resrec->{'borrowernumber'}
        and reservedate = '$resrec->{'reservedate'}'
        and biblionumber = $resrec->{'biblionumber'}";
      my $updsth = $dbh->prepare($updquery);
      $updsth->execute;
      $updsth->finish;
    }
  }
  $sth->finish;
  return ($resfound,$resrec);   
}
END { }       # module clean-up code here (global destructor)
