##############################################
# $Id: 99_I2C_HP03S.pm 5865 2014-05-14 23:00:12Z klauswitt $

package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
#use Error qw(:try);

use constant {
	HP03S_I2C_ADDRESS => '0x77',
};

##################################################
# Forward declarations
#
sub I2C_HP03S_Initialize($);
sub I2C_HP03S_Define($$);
sub I2C_HP03S_Attr(@);
sub I2C_HP03S_Poll($);
sub I2C_HP03S_Set($@);
sub I2C_HP03S_Undef($$);


my %sets = (
	'readValues' => 1,
);

sub I2C_HP03S_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_HP03S_Define';
	$hash->{InitFn}   = 'I2C_HP03S_Init';
	$hash->{AttrFn}   = 'I2C_HP03S_Attr';
	$hash->{SetFn}    = 'I2C_HP03S_Set';
	$hash->{UndefFn}  = 'I2C_HP03S_Undef';
	$hash->{I2CRecFn} = 'I2C_HP03S_I2CRec';

	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
				'roundPressureDecimal:0,1,2 roundTemperatureDecimal:0,1,2 ' .
				'cal_C1 cal_C2 cal_C3 cal_C4 cal_C5 cal_C6 cal_C7 cal_A cal_D cal_C cal_D ' .
						$readingFnAttributes;
}

sub I2C_HP03S_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	  $hash->{STATE} = "defined";

	if ($main::init_done) {
		eval { I2C_HP03S_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_HP03S_Catch($@) if $@;
	}
	return undef;
}

sub I2C_HP03S_Init($$) {
	my ( $hash, $args ) = @_;

	my $name = $hash->{NAME};

	if (defined $args && int(@$args) > 1)
 	{
		return "Define: Wrong syntax." . int(@$args) . " Usage:\n" .
				"define <name> I2C_HP03S [<i2caddress>]";
 	}

 	if (defined (my $address = shift @$args)) {
   	$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
   	return "$name I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
 	} else {
		$hash->{I2C_Address} = hex(HP03S_I2C_ADDRESS);
	}

	# default values
	$hash->{cal_C1} = 16409;
	$hash->{cal_C2} = 3090;
	$hash->{cal_C3} = 315;
	$hash->{cal_C4} = 1414;
	$hash->{cal_C5} = 34318;
	$hash->{cal_C6} = 5723;
	$hash->{cal_C7} = 2500;

	$hash->{cal_A} = 11;
	$hash->{cal_B} = 11;
	$hash->{cal_C} = 2**6;
	$hash->{cal_D} = 2**11;

	my $msg = '';
	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 5');
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	AssignIoPort($hash);
	$hash->{STATE} = 'Initialized';

#	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
#	$sendpackage{reg} = hex("AA");
#	$sendpackage{nbyte} = 22;
#	return "$name: no IO device defined" unless ($hash->{IODev});
#	my $phash = $hash->{IODev};
#	my $pname = $phash->{NAME};
#	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);

	return undef;
}

sub I2C_HP03S_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}


sub I2C_HP03S_Attr (@) {# hier noch Werteueberpruefung einfuegen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_HP03S_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
	if ($attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;

		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_HP03S_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'roundPressureDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val < 0 && $val > 2 ;
	} elsif ($attr eq 'roundTemperatureDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val < 0 && $val > 2 ;
	} elsif ($attr eq 'cal_C1') {
		if (defined($val) && $val >= 256 && $val <= 65535) {
			$hash->{cal_C1} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 256..65535';
		}
	} elsif ($attr eq 'cal_C2') {
		if (defined($val) && $val >= 0 && $val <= 8197) {
			$hash->{cal_C2} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 0..8197';
		}
	} elsif ($attr eq 'cal_C3') {
		if (defined($val) && $val >= 0 && $val <= 3000) {
			$hash->{cal_C3} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 0..3000';
		}
	} elsif ($attr eq 'cal_C4') {
		if (defined($val) && $val >= 0 && $val <= 4096) {
			$hash->{cal_C4} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 0..4096';
		}
	} elsif ($attr eq 'cal_C5') {
		if (defined($val) && $val >= 4096 && $val <= 65535) {
			$hash->{cal_C5} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 4096..65535';
		}
	} elsif ($attr eq 'cal_C6') {
		if (defined($val) && $val >= 0 && $val <= 16384) {
			$hash->{cal_C6} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 0..16384';
		}
	} elsif ($attr eq 'cal_C7') {
		if (defined($val) && $val >= 2400 && $val <= 2600) {
			$hash->{cal_C7} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 2400..2600';
		}
	} elsif ($attr eq 'cal_A') {
		if (defined($val) && $val >= 1 && $val <= 63) {
			$hash->{cal_A} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 1..63';
		}
	} elsif ($attr eq 'cal_B') {
		if (defined($val) && $val >= 1 && $val <= 63) {
			$hash->{cal_B} = $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 1..63';
		}
	} elsif ($attr eq 'cal_C') {
		if (defined($val) && $val >= 1 && $val <= 15) {
			$hash->{cal_C} = 2 ** $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 1..15';
		}
	} elsif ($attr eq 'cal_D') {
		if (defined($val) && $val >= 1 && $val <= 15) {
			$hash->{cal_D} = 2 ** $val;
		} else {
			$msg = 'Wrong $attr defined. Must be 1..15';
		}
	}
	return ($msg) ? $msg : undef;
}

sub I2C_HP03S_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	# Read values
	I2C_HP03S_Set($hash, ($name, 'readValues'));

	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_HP03S_Poll', $hash, 0);
	}
}

sub I2C_HP03S_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}

	if ($cmd eq 'readValues') {
		I2C_HP03S_readPressure($hash);
		I2C_HP03S_readTemperature($hash);
	}
}

sub I2C_HP03S_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_HP03S_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	}
	if ($clientmsg->{direction} && $clientmsg->{type} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			Log3 $hash, 5, "empfangen: $clientmsg->{received}";
			I2C_HP03S_GetPres ($hash, $clientmsg->{received}) if $clientmsg->{type} eq "pres" && $clientmsg->{nbyte} == 2;
			I2C_HP03S_GetTemp ($hash, $clientmsg->{received}) if $clientmsg->{type} eq "temp" && $clientmsg->{nbyte} == 2;
		}
	}
}

sub I2C_HP03S_GetTemp ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	my $name = $hash->{NAME};

	my $D2 = $raw[0] << 8 | $raw[1];
	my $D1 = ReadingsVal($name, "D1", 0);

	readingsSingleUpdate($hash,"D2", $D2, 1);

	my $dUT = $D2 - $hash->{cal_C5};
	if ($dUT >= 0) {
		$dUT = $dUT - (((($dUT * $dUT) / (2**14)) * $hash->{cal_A}) / $hash->{cal_C});
	} else {
		$dUT = $dUT - (((($dUT * $dUT) / (2**14)) * $hash->{cal_B}) / $hash->{cal_C});
	}

	my $offs = ($hash->{cal_C2} + (($hash->{cal_C4} - 1024) * $dUT) / 2**14) * 4;
	my $sens = $hash->{cal_C1} + ($hash->{cal_C3} * $dUT) / 2**10;
	my $x = (($sens * ($D1 - 7168)) / 2**14) - $offs;

	my $pressure = (($x * 10) / 2**5 + $hash->{cal_C7}) / 10;
	$pressure = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundPressureDecimal', 1) . 'f',
			$pressure
		);

	my $temperature = (250 + (($dUT * $hash->{cal_C6}) / 2**16) - ($dUT / $hash->{cal_D})) / 10;
	$temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			$temperature
		);

	readingsBeginUpdate($hash);
	readingsBulkUpdate(
		$hash,
		'state',
		'P: ' . $pressure . ' T: ' . $temperature
	);
	readingsBulkUpdate($hash, 'pressure', $pressure);
	readingsBulkUpdate($hash, 'temperature', $temperature);
	readingsEndUpdate($hash, 1);
}

sub I2C_HP03S_GetPres ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	my $name = $hash->{NAME};

	my $D1 = $raw[0] << 8 | $raw[1];

	readingsSingleUpdate($hash,"D1", $D1, 1);
}


sub I2C_HP03S_readTemperature($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};

	# Write 0xFFE8 to device. This requests a reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{reg} = hex("FF");
	$i2creq->{data} = hex("E8");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(50000); #min 40ms

	# Read the four byte result from device
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
	$i2cread->{reg} = hex("FD");
	$i2cread->{nbyte} = 2;
	$i2cread->{type} = "temp";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);

	return;
}

sub I2C_HP03S_readPressure($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};

	# Write 0xFFF0 to the device. This starts
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{reg} = hex("FF");
	$i2creq->{data} = hex("F0");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(50000); #min 40ms

	# Read the four byte result from device
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
	$i2cread->{reg} = hex("FD");
	$i2cread->{nbyte} = 2;
	$i2cread->{type} = "pres";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);

	return; # $retVal;
}

1;

=pod
=begin html

<a name="I2C_HP03S"></a>
<h3>I2C_HP03S</h3>
<ul>
	<a name="I2C_HP03S"></a>
		Provides an interface to the HP03S I2C Humidity sensor from <a href="www.sensirion.com">Sensirion</a>.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_SHT21Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_HP03S [&lt;I2C Address&gt;]</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
	</ul>
	<a name="I2C_HP03SSet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Reads the current temperature and humidity values from sensor.<br><br>
	</ul>
	<a name="I2C_HP03SAttr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundHumidityDecimal<br>
			Number of decimal places for humidity value<br>
			Default: 1, valid values: 0 1 2<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Number of decimal places for temperature value<br>
			Default: 1, valid values: 0,1,2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_HP03S"></a>
<h3>I2C_HP03S</h3>
<ul>
	<a name="I2C_SHT21"></a>
		Erm&ouml;glicht die Verwendung eines HP03S I2C Feuchtesensors von <a href="www.sensirion.com">Sensirion</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_SHT21Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_SHT21 [&lt;I2C Address&gt;]</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
	</ul>
	<a name="I2C_SHT21Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur und Feuchte Werte vom Sensor lesen.<br><br>
	</ul>
	<a name="I2C_SHT21Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundHumidityDecimal<br>
			Anzahl Dezimalstellen f&uuml;r den Feuchtewert<br>
			Standard: 1, g&uuml;ltige Werte: 0 1 2<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Anzahl Dezimalstellen f&uuml;r den Temperaturwert<br>
			Standard: 1, g&uuml;ltige Werte: 0,1,2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html_DE

=cut