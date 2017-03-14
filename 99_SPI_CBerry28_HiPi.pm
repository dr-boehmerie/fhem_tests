
package main;

use strict;
use warnings;

use HiPi::Device::GPIO;
use HiPi::Constant qw( :raspberry );

use HiPi::Device::SPI;
use HiPi::Device::SPI qw( :spi );

use Imager;
use Imager::Fill;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
use Error qw(:try);
use Sys::Hostname;
use Socket;	# für die IP-Adresse
use IO::Socket::INET;

use constant {
#color modes (color depths) { CM_262K, CM_65K };
	CM_262K			=> 0,
	CM_65K			=> 1,

# TFT dimensions
	DISPLAY_WIDTH	=> 320,
	DISPLAY_HEIGHT	=> 240,
	PICTURE_PIXELS	=> ( 320 * 240 ),
};

my %sets = (
	'clear' => "",
	'textx' => "",
	'texty' => "",
	'textfont' => "",
	'textcolor' => "",
	'textsize' => "",
	'text' => "",
	'update' => "",
	'load' => "",
	'save' => "",
);

##################################################
# Forward declarations
#
sub SPI_CBerry28_Initialize($);
sub SPI_CBerry28_Define($$);
sub SPI_CBerry28_Attr(@);
sub SPI_CBerry28_Poll($);
sub SPI_CBerry28_Set($@);
sub SPI_CBerry28_Get($);
sub SPI_CBerry28_Undef($$);

sub SPI_CBerry28_SetPosX($$);
sub SPI_CBerry28_SetPosY($$);
sub SPI_CBerry28_SetTextColor($$);
sub SPI_CBerry28_SetTextFont($$);
sub SPI_CBerry28_SetTextSize($$);
sub SPI_CBerry28_SetText($$);
sub SPI_CBerry28_SetUpdate($$);

sub SPI_CBerry28_Init($$);
sub SPI_CBerry28_UnInit($$);
sub SPI_CBerry28_SetBacklightPWM($$);

sub SPI_CBerry28_NewImage($$);
sub SPI_CBerry28_LoadImage($$$);
sub SPI_CBerry28_Box($@);
sub SPI_CBerry28_Box2($@);
sub SPI_CBerry28_Box3($@);
sub SPI_CBerry28_Box4($@);
sub SPI_CBerry28_SetFont($@);
sub SPI_CBerry28_Text($@);
sub SPI_CBerry28_SaveImage($$$);
sub SPI_CBerry28_SaveImageBmp($$);
sub SPI_CBerry28_SendImageToTFT($);


# This idea was stolen from Net::Address::IP::Local::connected_to()
sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => '198.41.0.4', # a.root-servers.net
        PeerPort    => '53', # DNS
    );

    # A side-effect of making a socket connection is that our IP address
    # is available from the 'sockhost' method
    my $local_ip_address = $socket->sockhost;

    return $local_ip_address;
}

=head2 SPI_CBerry28_Initialize
	Title:		SPI_CBerry28_Initialize
	Function:	Implements the initialize function.
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_CBerry28_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'SPI_CBerry28_Define';
	$hash->{AttrFn}   = 'SPI_CBerry28_Attr';
	$hash->{SetFn}    = 'SPI_CBerry28_Set';
	$hash->{GetFn}    = 'SPI_CBerry28_Get';
	$hash->{UndefFn}  = 'SPI_CBerry28_Undef';

	$hash->{AttrList} = 'do_not_notify:0,1 showtime:0,1,2,3,4 initDone:0,1 ' .
	                    'loglevel:0,1,2,3,4,5,6 poll_interval:1,2,5,10,20,30 ' . $readingFnAttributes;
}

=head2 SPI_CBerry28_Define
	Title:		SPI_CBerry28_Define
	Function:	Implements the define function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash
				-argument2 => string

=cut

sub SPI_CBerry28_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];

	Log3 $name, 3, "SPI_CBerry28_Define start";
	my $msg = '';
	if( (@a < 3)) {
		$msg = 'wrong syntax: define <name> SPI_CBerry28 spi_device [gpio_rst_pin gpio_rs_pin [gpio_pwm_pin]]';
		return undef;
	}

#	$hash->{lines} = 4;
#	$hash->{chars} = 20;
	$hash->{textx} = 0;
	$hash->{texty} = 0;
	$hash->{textcolor} = 'black';
#	$hash->{Timeout} = 200000;
	$hash->{logLevel} = 5;
	$hash->{initDone} = 0;
	$hash->{active} = 0;

	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 1');

	if ($msg) {
		Log (1, $msg);
		return $msg;
	}

	# Initialize
	if (SPI_CBerry28_Init($hash, $dev) == 1) {
		my $host = hostname();
		my $address = get_local_ip_address();	#inet_ntoa(scalar gethostbyname( $host || 'localhost' ));

		# Welcome Message
		SPI_CBerry28_NewImage($hash, 'white');
		SPI_CBerry28_Box2($hash, 0, 0, DISPLAY_WIDTH, 64, 'blue', 180);
		SPI_CBerry28_Box3($hash, 0, 0, DISPLAY_WIDTH, DISPLAY_HEIGHT, 1, 'blue');

		# Init Text Font
		SPI_CBerry28_SetFont($hash, 'droid/DroidSans.ttf', 20);

		SPI_CBerry28_Text($hash, 10, 20, 'white', 'Hello from fhem!');
		SPI_CBerry28_Text($hash, 10, 40, 'white', 'IP = ' . $address);
		SPI_CBerry28_Text($hash, 10, 60, 'white', 'Host = ' . $host);

		# Send image to TFT
		SPI_CBerry28_SendImageToTFT($hash);

		readingsSingleUpdate($hash, 'state', 'Initialized', 1);
		
	} else {
		return $name . ': Error! SPI_CBerry28_Init failed';
	}
	Log3 $name, $hash->{logLevel}, "SPI_CBerry28_Define end";

	return undef;
}

=head2 SPI_CBerry28_Attr
	Title:		SPI_CBerry28_Attr
	Function:	Implements AttrFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => array

=cut

sub SPI_CBerry28_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	Log3 $name, $hash->{logLevel}, "SPI_CBerry28_Attr: attr " . $attr . " val " . $val;
	if ($attr eq 'poll_interval') {
		my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;

		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'SPI_CBerry28_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'loglevel') {
		my $logLevel = (defined($val) && looks_like_number($val) && $val >= 0 && $val < 7) ? $val : 0;

		$hash->{logLevel} = $logLevel;
		
	} elsif ($attr eq 'showtime') {
		my $showtime = (defined($val) && looks_like_number($val) && $val >= 0 && $val < 5) ? $val : 0;

		$hash->{showtime} = $showtime;
	}

	return ($msg) ? $msg : undef;
}

=head2 SPI_CBerry28_Poll
	Title:		SPI_CBerry28_Poll
	Function:	Start polling the sensor at interval defined in attribute
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_CBerry28_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	my @curtime = localtime;

	# print a nice representation
	my $text = sprintf("%d-%02d-%02d %02d:%02d",
		$curtime[5] + 1900, $curtime[4] + 1, $curtime[3], $curtime[2], $curtime[1]);

	$hash->{lastUpdateTime} = $text;

	if ($hash->{showtime}) {
		my $x = 0;
		my $y = 0;
		my $dx = 160;
		my $dy = 20;
		
		if ($hash->{showtime} == 1) {
			# Top Left
		
		} elsif ($hash->{showtime} == 2) {
			# Top Right
			$x = DISPLAY_WIDTH - $dx;
		
		} elsif ($hash->{showtime} == 3) {
			# Bottom Right
			$x = DISPLAY_WIDTH - $dx;
			$y = DISPLAY_HEIGHT - $dy;
		
		} elsif ($hash->{showtime} == 4) {
			# Bottom Left
			$y = DISPLAY_HEIGHT - $dy;
		}
		# Background and Text
		SPI_CBerry28_Box($hash, $x, $y, $dx, $dy, 'gray');
		SPI_CBerry28_Text($hash, $x + 2, $y + $dy - 2, 'black', $text);
	}	
	# Send Image to TFT
	SPI_CBerry28_SendImageToTFT($hash);

	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'SPI_CBerry28_Poll', $hash, 0);
	}
}

=head2 SPI_CBerry28_Get
	Title:		SPI_CBerry28_Get
	Function:	Implements GetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Get($) {
	my ( $hash ) = @_;
	my $name = $hash->{NAME};

#	my $lux = I2C_TSL2561_CalculateLux($hash);
#	readingsBeginUpdate($hash);
#	readingsBulkUpdate($hash,"luminosity",$lux);
#	readingsBulkUpdate($hash,"broadband",$hash->{broadband});
#	readingsBulkUpdate($hash,"ir",$hash->{ir});
#	readingsEndUpdate($hash,1);

	#readingsSingleUpdate($hash,"failures",ReadingsVal($hash->{NAME},"failures",0)+1,1);
}

=head2 SPI_CBerry28_Set
	Title:		SPI_CBerry28_Set
	Function:	Implements SetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Set($@) {
	my ($hash, @a) = @_;

	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}

	if ($cmd eq 'clear') {
		SPI_CBerry28_NewImage($hash, $val);
		return undef;
	}
	if ($cmd eq 'textx') {
		SPI_CBerry28_SetPosX($hash, $val);
		return undef;
	}
	if ($cmd eq 'texty') {
		SPI_CBerry28_SetPosY($hash, $val);
		return undef;
	}
	if ($cmd eq 'textcolor') {
		SPI_CBerry28_SetTextColor($hash, $val);
		return undef;
	}
	if ($cmd eq 'textfont') {
		SPI_CBerry28_SetTextFont($hash, $val);
		return undef;
	}
	if ($cmd eq 'textsize') {
		SPI_CBerry28_SetTextSize($hash, $val);
		return undef;
	}
	if ($cmd eq 'text') {
		SPI_CBerry28_SetText($hash, $val);
		return undef;
	}
	if ($cmd eq 'update') {
		SPI_CBerry28_SetUpdate($hash, $val);
		return undef;
	}
	if ($cmd eq 'load') {
		SPI_CBerry28_LoadImage($hash, 'white', $val);
		return undef;
	}
	if ($cmd eq 'save') {
		SPI_CBerry28_SaveImageBmp($hash, $val);
		return undef;
	}
#	if ($cmd eq 'box') {
#		SPI_CBerry28_SetBox($hash, $val);
#		return undef;
#	}
	return 'Unhandled argument ' . $cmd;
}

=head2 SPI_CBerry28_Undef
	Title:		SPI_CBerry28_Undef
	Function:	Implements UndefFn function.
	Returns:	undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	SPI_CBerry28_UnInit($hash, 0);

	return undef;
}

sub SPI_CBerry28_SetPosX($$)
{
	my ($hash, $pos) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetPosX: ' . $pos;

	$hash->{textx} = $pos;
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetPosY($$)
{
	my ($hash, $pos) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetPosY: ' . $pos;

	$hash->{texty} = $pos;
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetTextColor($$)
{
	my ($hash, $color) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetTextColor: ' . $color;

	$hash->{textcolor} = $color;
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetTextFont($$)
{
	my ($hash, $font) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetTextFont: ' . $font;

	SPI_CBerry28_SetFont($hash, $font, $hash->{fontSize});
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetTextSize($$)
{
	my ($hash, $size) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetTextSize: ' . $size;
	
	$hash->{fontsize} = $size;
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetText($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetText: ' . $text;

	SPI_CBerry28_Text($hash, $hash->{textx}, $hash->{texty}, $hash->{textcolor}, $text);
	$retVal = 1;

	return $retVal;
}

sub SPI_CBerry28_SetUpdate($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetUpdate: ' . $val;

	SPI_CBerry28_SendImageToTFT($hash);
	$retVal = 1;

	return $retVal;
}


use constant {
#color modes (color depths) { CM_262K, CM_65K };
#	CM_262K			=> 0,
#	CM_65K			=> 1,

# TFT dimensions
#	DISPLAY_WIDTH	=> 320,
#	DISPLAY_HEIGHT	=> 240,
#	PICTURE_PIXELS	=> ( 320 * 240 ),

# ST register -> see datasheet ST7789
	NOP				=> 0x00,
	SWRESET 		=> 0x01,
	RDDID 			=> 0x04,
	RDDST 			=> 0x09,
	RDDPM 			=> 0x0A,
	RDDMADCTL 		=> 0x0B,
	RDDCOLMOD 		=> 0x0C,
	RDDIM 			=> 0x0D,
	RDDSM 			=> 0x0E,
	RDDSDR 			=> 0x0F,
	SLPIN 			=> 0x10,
	SLPOUT			=> 0x11,
	PTLON			=> 0x12,
	NORON			=> 0x13,
	INVOFF			=> 0x20,
	INVON			=> 0x21,
	GAMSET			=> 0x26,
	DISPOFF			=> 0x28,
	DISPON			=> 0x29,
	CASET			=> 0x2A,
	RASET			=> 0x2B,
	RAMWR			=> 0x2C,
	RAMRD			=> 0x2E,
	PTLAR			=> 0x30,
	VSCRDEF			=> 0x33,
	TEOFF			=> 0x34,
	TEON			=> 0x35,
	MADCTL			=> 0x36,
	VSCRSADD		=> 0x37,
	IDMOFF			=> 0x38,
	IDMON			=> 0x39,
	COLMOD			=> 0x3A,
	RAMWRC			=> 0x3C,
	RAMRDC			=> 0x3E,
	TESCAN			=> 0x44,
	RDTESCAN		=> 0x45,
	WRDISBV			=> 0x51,
	RDDISBV			=> 0x52,
	WRCTRLD			=> 0x53,
	RDCTRLD			=> 0x54,
	WRCACE			=> 0x55,
	RDCABC			=> 0x56,
	WRCABCMB		=> 0x5E,
	RDCABCMB		=> 0x5F,
	RDID1			=> 0xDA,
	RDID2			=> 0xDB,
	RDID3			=> 0xDC,

	RAMCTRL			=> 0xB0,
	RGBCTRL			=> 0xB1,
	PORCTRL			=> 0xB2,
	FRCTRL1 		=> 0xB3,
	GCTRL			=> 0xB7,
	DGMEN			=> 0xBA,
	VCOMS			=> 0xBB,
	LCMCTRL			=> 0xC0,
	IDSET			=> 0xC1,
	VDVVRHEN		=> 0xC2,
	VRHS			=> 0xC3,
	VDVSET			=> 0xC4,
	VCMOFSET		=> 0xC5,
	FRCTRL2			=> 0xC6,
	CABCCTRL		=> 0xC7,
	REGSEL1			=> 0xC8,
	REGSEL2 		=> 0xCA,
	PWCTRL1			=> 0xD0,
	VAPVANEN		=> 0xD0,
	PVGAMCTRL		=> 0xE0,
	NVGAMCTRL		=> 0xE1,
	DGMLUTR			=> 0xE2,
	DGMLUTB			=> 0xE3,
	GATECTRL		=> 0xE4,
	PWCTRL2			=> 0xE8,
	EQCTRL			=> 0xE9,
	PROMCTRL		=> 0xEC,
	PROMEN			=> 0xFA,
	NVMSET			=> 0xFC,
	PROMACT			=> 0xFE,

#	MOSI			=> RPI_V2_GPIO_P1_19,
#	SCLK			=> RPI_V2_GPIO_P1_23,
#	SPI_CE0			=> RPI_V2_GPIO_P1_24,
	PIN_ST_RST		=> RPI_PAD1_PIN_22,	#RPI_V2_GPIO_P1_22,
	PIN_ST_RS		=> RPI_PAD1_PIN_15,	#RPI_V2_GPIO_P1_15,
	PIN_BL_PWM		=> RPI_PAD1_PIN_12,	#RPI_V2_GPIO_P1_12,

# PWM settings
	PWM_CHANNEL		=> 0,
	PWM_RANGE		=> 255,
};

my %fontlist = (
	'0'  => "droid/DroidNaskh-Bold.ttf",
	'1'  => "droid/DroidNaskh-Regular.ttf",
	'2'  => "droid/DroidSans.ttf",
	'3'  => "droid/DroidSansArmenian.ttf",
	'4'  => "droid/DroidSans-Bold.ttf",
	'5'  => "droid/DroidSansEthiopic-Bold.ttf",
	'6'  => "droid/DroidSansEthiopic-Regular.ttf",
	'7'  => "droid/DroidSansFallbackFull.ttf",
	'8'  => "droid/DroidSansGeorgian.ttf",
	'9'  => "droid/DroidSansHebrew-Bold.ttf",
	'10' => "droid/DroidSansHebrew-Regular.ttf",
	'11' => "droid/DroidSansJapanese.ttf",
	'12' => "droid/DroidSansMono.ttf",
	'13' => "droid/DroidSansThai.ttf",
	'14' => "droid/DroidSerif-Bold.ttf",
	'15' => "droid/DroidSerif-BoldItalic.ttf",
	'16' => "droid/DroidSerif-Italic.ttf",
	'17' => "droid/DroidSerif-Regular.ttf",
	'18' => "freefont/FreeMono.ttf",
	'19' => "freefont/FreeMonoBold.ttf",
	'20' => "freefont/FreeMonoBoldOblique.ttf",
	'21' => "freefont/FreeMonoOblique.ttf",
	'22' => "freefont/FreeSans.ttf",
	'23' => "freefont/FreeSansBold.ttf",
	'24' => "freefont/FreeSansBoldOblique.ttf",
	'25' => "freefont/FreeSansOblique.ttf",
	'26' => "freefont/FreeSerif.ttf",
	'27' => "freefont/FreeSerifBold.ttf",
	'28' => "freefont/FreeSerifBoldItalic.ttf",
	'29' => "freefont/FreeSerifItalic.ttf",
);

# write byte to register
sub SPI_CBerry28_WriteReg($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_WriteReg: $val\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteReg: ' . $val;

	eval {
		$hash->{pinRS}->value(0);

		my @temp = ($val);
		my $input = pack('C1', @temp);
		my $len = length($input);
	#	print "SPI_CBerry28_WriteReg: 1; $len\n";
		
		my $output = $hash->{devSPI}->transfer( $input );
	#	my @resp = unpack ('C1', $output);

	} or do {
		my $e = $@;
#		print "SPI_CBerry28_WriteReg: exception $e\n";
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteReg: exception (' . $e . ')';
	};
}

# write byte to tft
sub SPI_CBerry28_WriteData($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_WriteData: $val\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteData: ' . $val;

	eval {
		$hash->{pinRS}->value(1);
		
		my @temp = ($val);
		my $input = pack('C1', @temp);
		my $len = length($input);
	#	print "SPI_CBerry28_WriteData: 1; $len\n";
		
		my $output = $hash->{devSPI}->transfer( $input );
	#	my @resp = unpack ('C1', $output);
		
	} or do {
		my $e = $@;
#		print "SPI_CBerry28_WriteData: exception $e\n";
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteData: exception (' . $e . ')';
	};
}

# write multiple bytes to tft
sub SPI_CBerry28_WriteMultiData($$@)
{
	my ($hash, $cnt, @vals) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_WriteMultiData: $cnt; @vals\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteMultiData: ' . $cnt;

	eval {
		$hash->{pinRS}->value(1);

		my $input = pack('C*', @vals);
		my $len = length($input);
#		print "SPI_CBerry28_WriteMultiData: $cnt; $len\n";

		my $output = $hash->{devSPI}->transfer( $input );
	#	my @resp = unpack ('C*', $output);
		
	} or do {
		my $e = $@;
#		print "SPI_CBerry28_WriteMultiData: exception $e\n";
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteMultiData: exception (' . $e . ')';
	};
}

# write command to a register
sub SPI_CBerry28_SetRegister($$$@)
{
	my ($hash, $reg, $cnt, @vals) = @_;

#	print "SPI_CBerry28_SetRegister: $reg; $cnt; @vals\n";

	SPI_CBerry28_WriteReg ($hash, $reg);

	SPI_CBerry28_WriteMultiData ($hash, $cnt, @vals);
}

# define area of frame memory where MCU can access
sub SPI_CBerry28_SetRow($$$)
{
	my ($hash, $row_start, $row_end) = @_;
	my $name = $hash->{NAME};

	SPI_CBerry28_SetRegister ($hash,
		RASET, 4,
		(($row_start >> 8) & 0xFF, $row_start & 0xFF,
		($row_end >> 8) & 0xFF, $row_end & 0xFF));
}

sub SPI_CBerry28_SetColumn($$$)
{
	my ($hash, $col_start, $col_end) = @_;
	my $name = $hash->{NAME};

#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SetColumn: ' . $col_start . '; ' . $col_end;

	SPI_CBerry28_SetRegister ($hash,
		CASET, 4,
		(($col_start >> 8) & 0xFF, $col_start & 0xFF,
		($col_end >> 8) & 0xFF, $col_end & 0xFF));
}

# initialization of ST7789
sub SPI_CBerry28_InitTFTcontroller($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_InitTFTcontroller:\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_InitTFTcontroller:';

	# *************** wakeup display
	SPI_CBerry28_WriteReg($hash, SLPOUT);
	usleep(120 * 1000);

	# *************** display and color format setting

	# write data from top-left to bottom-right
	SPI_CBerry28_SetRegister($hash, MADCTL, 1, (0xA0));	# 0x00

	if (CM_262K == 1) {
		# 18bit/pixel
		# 262K-colors (RGB 6-6-6)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, (0x06));
	} else {
		# 16bit/pixel
		# 65K-colors (RGB 5-6-5)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, (0x05));
	}

	# *************** ST7789 porch setting

	# seperate porch control = disabled
	# front porch in normal mode  = 13 CLK pulse
	# back porch in normal mode   = 13 CLK pulse
	# front porch in idle mode    =  3 CLK pulse
	# back porch in idle mode     =  3 CLK pulse
	# front porch in partial mode =  3 CLK pulse
	# back porch in partial mode  =  3 CLK pulse
	SPI_CBerry28_SetRegister($hash, PORCTRL, 5, (0x0C, 0x0C, 0x00, 0x33, 0x33));

	# *************** ST7789 Power setting

	# VGH =  12.26V
	# VGL = -10.43V
	SPI_CBerry28_SetRegister($hash, GCTRL, 1, (0x35));

	# VDV and VRH register value comes from command line
	SPI_CBerry28_SetRegister($hash, VDVVRHEN, 1, (0x1F));

	# VAP = 4.7 + Vcom + Vcom_offset + 0.5*VDV
	SPI_CBerry28_SetRegister($hash, VRHS, 1, (0x2C));

	# VDV = 0V
	SPI_CBerry28_SetRegister($hash, VDVSET, 1, (0x01));

	# Vcom = 0.875V
	SPI_CBerry28_SetRegister($hash, VCOMS, 1, (0x17));

	# Vcom_offset = 0V
	SPI_CBerry28_SetRegister($hash, VCMOFSET, 1, (0x20));

	# AVDD =  6.6V
	# AVCL = -4.8V
	# VDS  =  2.3V
	SPI_CBerry28_SetRegister($hash, PWCTRL1, 2, (0xA4, 0xA1));

	# *************** ST7789 gamma setting

	SPI_CBerry28_SetRegister($hash, PVGAMCTRL, 14, (0xD0, 0x00, 0x14, 0x15, 0x13, 0x2C, 0x42, 0x43, 0x4E, 0x09, 0x16, 0x14, 0x18, 0x21));
	SPI_CBerry28_SetRegister($hash, NVGAMCTRL, 14, (0xD0, 0x00, 0x14, 0x15, 0x13, 0x0B, 0x43, 0x55, 0x53, 0x0C, 0x17, 0x14, 0x23, 0x20));

	# *************** miscellaneous settings

	# define area (start row, end row, start column, end column) of frame memory where MCU can access
	SPI_CBerry28_SetRow($hash, 0, DISPLAY_HEIGHT - 1 );
	SPI_CBerry28_SetColumn($hash, 0, DISPLAY_WIDTH - 1 );

	# *************** display on
	SPI_CBerry28_WriteReg($hash, DISPON);
}

# initialization of GPIO and SPI
sub SPI_CBerry28_InitBoard ($$)
{
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_InitBoard: $dev\n";

	my $resp = 0;
	
	# check for existing spi device
	my $spiModulesLoaded = 0;
	$spiModulesLoaded = 1 if -e $dev;

	if ($spiModulesLoaded) {
		if (-r $dev && -w $dev) {
			# *************** set the pins to be an output and turn them on
			eval {
				# Init SPI
				$hash->{devSPI} = HiPi::Device::SPI->new(
					devicename	=> $dev,
					speed		=> SPI_SPEED_MHZ_16,
					busmode		=> SPI_MODE_0,
					bitsperword	=> 8,
					delay		=> 1,
				);
			#	print "SPI_CBerry28_InitBoard: SPI device created\n";
#				Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_InitBoard: SPI device created';
				
			#	my $ret1 = $hash->{devSPI}->set_bus_maxspeed(SPI_SPEED_MHZ_2);
			#	my $spd = $hash->{devSPI}->speed;
			#	print "SPI_CBerry28_InitBoard: SPI speed: $ret1; $spd;\n";
			
				my $fh = $hash->{devSPI}->fh;
				my $fno = $hash->{devSPI}->fno;
				my $delay = $hash->{devSPI}->delay;
				my $speed = $hash->{devSPI}->speed;
				my $bpw = $hash->{devSPI}->bitsperword;
#				print "SPI_CBerry28_InitBoard: SPI device created: $fh; $fno; $delay; $speed; $bpw\n";
				Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_InitBoard: SPI device created: $fh; $fno; $delay; $speed; $bpw';

				# Control Pins using GPIO
				$hash->{devGPIO} = HiPi::Device::GPIO->new();
#				print "SPI_CBerry28_InitBoard: GPIO device created\n";
				Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_InitBoard: GPIO device created';
				
#				print "SPI_CBerry28_InitBoard: configuring pins: " . PIN_ST_RST . ", " . PIN_ST_RS . ", " . PIN_BL_PWM . "\n";
				$hash->{pinRST} = $hash->{devGPIO}->export_pin( PIN_ST_RST );
				$hash->{pinRS}  = $hash->{devGPIO}->export_pin( PIN_ST_RS );
				$hash->{pinPWM} = $hash->{devGPIO}->export_pin( PIN_BL_PWM );
#				print "SPI_CBerry28_InitBoard: PINs exported: $hash->{pinRST}; $hash->{pinRS}; $hash->{pinPWM}\n";
				
				$hash->{pinRST}->mode( RPI_PINMODE_OUTP );
				$hash->{pinRST}->value(0);
#				print "SPI_CBerry28_InitBoard: pin RST set to output\n";

				$hash->{pinRS}->mode( RPI_PINMODE_OUTP );
				$hash->{pinRS}->value(0);
#				print "SPI_CBerry28_InitBoard: pin RS set to output\n";
				
				$hash->{pinPWM}->mode( RPI_PINMODE_OUTP );	# TODO: AltFunc!
				$hash->{pinPWM}->value(0);
#				print "SPI_CBerry28_InitBoard: pin PWM set to output\n";

			# Clock divider is set to 16.
			# 1.2MHz/1024 = 1171.875Hz
		#	bcm2835_pwm_set_clock(BCM2835_PWM_CLOCK_DIVIDER_16);
		#	bcm2835_pwm_set_mode(PWM_CHANNEL, 1, 1);
		#	bcm2835_pwm_set_range(PWM_CHANNEL, PWM_RANGE);

				$resp = 1;
				
			} or do {
				my $e = $@;
#				print "SPI_CBerry28_InitBoard: exception $e\n";
				Log3 $name, 1, ": Error! SPI_CBerry28_InitBoard: exception $e";
			}
		} else {
#			my @groups = split '\s', $(;
#			print "Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " . getgrgid($_) . " " foreach(@groups);
			my @groups = split '\s', $(;
		#	return "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " . getgrgid($_) . " " foreach(@groups);
			Log3 $name, 1, ": Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " . getgrgid($_) . " " foreach(@groups);
		}
	} else {
#		my $devices = HiPi::Device::SPI->get_device_list();
#		print 'Error! SPI device not found: ' . $dev . '. Please check that these kernelmodules are loaded: spi_bcm2708, spidev ' . $devices;
		my $devices = HiPi::Device::SPI->get_device_list();
#		return $name . ': Error! SPI device not found: ' . $dev . '. Please check that these kernelmodules are loaded: spi_bcm2708, spidev ' . $devices;
		Log3 $name, 1, ': Error! SPI device not found: ' . $dev . '. Please check that these kernelmodules are loaded: spi_bcm2708, spidev ' . $devices;
	}
	return $resp;
}


# hard reset of the tft controller
sub SPI_CBerry28_HardReset($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_HardReset:\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_HardReset:';

	eval {
		usleep(1 * 1000);
		$hash->{pinRST}->value(0);
		usleep(10 * 1000);
		$hash->{pinRST}->value(1);
		usleep(120 * 1000);
	} or do {
		my $e = $@;
#		print "SPI_CBerry28_HardReset: exception $e\n";
		Log3 $name, 1, 'ERROR: SPI_CBerry28_HardReset: exception (' . $e . ')';
	}
}

# set PWM value for backlight -> 0 (0% PWM) - 1024 (100% PWM)
sub SPI_CBerry28_SetBacklightPWM($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

#	print "SPI_CBerry28_SetBacklightPWM: $val\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SetBacklightPWM: ' . $val;

	if ($hash->{initDone} && $hash->{initDone} == 1) {
		eval {
		#	bcm2835_pwm_set_data( PWM_CHANNEL, BL_value );
			# TODO: PWM value
			if ($val > 0) {
				$hash->{pinPWM}->value(1);
			} else {
				$hash->{pinPWM}->value(0);
			}
		#	HiPi::Wiring::pwmWrite(BL_PWM, $val)
		} or do {
			my $e = $@;
#			print "SPI_CBerry28_SetBacklightPWM: exception $e\n";
			Log3 $name, 1, 'ERROR: SPI_CBerry28_SetBacklightPWM: exception (' . $e . ')';
		}
	}
}

sub SPI_CBerry28_Init($$)
{		
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};
	my $rval;
	
#	print "SPI_CBerry28_Init: $hash\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_Init:';

	$hash->{initDone} = SPI_CBerry28_InitBoard($hash, $dev);
	
#	print "SPI_CBerry28_Init: $hash->{initDone}\n";

	if ($hash->{initDone} == 1) {
	#	print "SPI_CBerry28_Init: PINs: $hash->{pinRST}; $hash->{pinRS}; $hash->{pinPWM}\n";
	#	my @names = keys $hash;
	#	print "SPI_CBerry28_Init: keys: @names\n";

		# Initialize Display
		SPI_CBerry28_HardReset($hash);
		SPI_CBerry28_InitTFTcontroller($hash);
		
		SPI_CBerry28_SetBacklightPWM($hash, 255);
		
		# Clear Display
	#	SPI_CBerry28_Clear($hash);

		$rval = 1;

	} else {
#		print "Error! Hardware setup failed!\n";
		
		$rval = 0;
	}
	
	return $rval;
}

sub SPI_CBerry28_UnInit($$)
{		
	my ($hash, $releasePins) = @_;
	my $name = $hash->{NAME};
	
#	print "SPI_CBerry28_UnInit: $hash\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_UnInit:';

	eval {
		if (exists($hash->{devSPI})) {
#			print "SPI_CBerry28_Init: Closing SPI $hash->{devSPI}\n";
			$hash->{devSPI}->close ();
			delete $hash->{devSPI};
		}

		if (exists($hash->{devGPIO}) && $releasePins == 1) {
			if (exists($hash->{pinRST})) {
#				print "SPI_CBerry28_Init: unexporting PIN " . PIN_ST_RST . " $hash->{pinRST}\n";
				$hash->{devGPIO}->unexport_pin( PIN_ST_RST );
			}
			if (exists($hash->{pinRS})) {
#				print "SPI_CBerry28_Init: unexporting PIN " . PIN_ST_RS . " $hash->{pinRS}\n";
				$hash->{devGPIO}->unexport_pin( PIN_ST_RS );
			}
			if (exists($hash->{pinPWM})) {
#				print "SPI_CBerry28_Init: unexporting PIN " . PIN_BL_PWM . " $hash->{pinPWM}\n";
				$hash->{devGPIO}->unexport_pin( PIN_BL_PWM );
			}
		}
	} or do {
		my $e = $@;
#		print "SPI_CBerry28_UnInit: exception $e\n";
		Log3 $name, 1, 'ERROR: SPI_CBerry28_UnInit: exception (' . $e . ')';
	}
}


sub SPI_CBerry28_NewImage($$)
{
	my ($hash, $bg_color) = @_;
	my $name = $hash->{NAME};
	
#	print "SPI_CBerry28_NewImage:\n";
	$hash->{filename} = "";

	my $image = Imager->new(xsize => DISPLAY_WIDTH, ysize => DISPLAY_HEIGHT);
	$image->box(filled => 1, color => $bg_color);

	$hash->{image} = $image;
	return $image
}

sub SPI_CBerry28_LoadImage($$$)
{
	my ($hash, $bg_color, $filename) = @_;
	my $name = $hash->{NAME};
	
#	print "SPI_CBerry28_LoadImage: $filename\n";

	my $image = Imager->new(xsize => DISPLAY_WIDTH, ysize => DISPLAY_HEIGHT);
	$image->box(filled => 1, color => $bg_color);
	
	if ($image->read(file => $filename)) {
		$hash->{filename} = $filename;

		if ($image->getwidth > DISPLAY_WIDTH || $image->getheight > DISPLAY_HEIGHT) {
			# scale to fit TFT
#			print "  scaling image (" . $image->getwidth . "," . $image->getheight . ") to (" . DISPLAY_WIDTH . "," . DISPLAY_HEIGHT . ")\n";
			$image = $image->scale(xpixels => DISPLAY_WIDTH, ypixels => DISPLAY_HEIGHT, type => 'nonprop');
		}
	} else {
#		print "SPI_CBerry28_LoadImage: failed to read file $filename with error:" . Imager->errstr . "\n";
		$hash->{filename} = "Failed to read file $filename with error:" . Imager->errstr;
		
		my $image = Imager->new(xsize => DISPLAY_WIDTH, ysize => DISPLAY_HEIGHT);
		$image->box(filled => 1, color => $bg_color);
	}

	$hash->{image} = $image;
	return $image
}

sub SPI_CBerry28_Box($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	
	my $x = $a[0];
	my $y = $a[1];
	my $dx = $a[2];
	my $dy = $a[3];
	my $color = $a[4];
	
#	print "SPI_CBerry28_Box:\n";

	if ($hash->{image}) {
		$hash->{image}->box(xmin => $x, ymin => $y, xmax => $x + $dx - 1, ymax => $y + $dy - 1, filled => 1, color => $color);
	}
}

sub SPI_CBerry28_Box2($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	
	my $x = $a[0];
	my $y = $a[1];
	my $dx = $a[2];
	my $dy = $a[3];
	my $color = $a[4];
	my $alpha = $a[5];
	
#	print "SPI_CBerry28_Box2:\n";

	if ($hash->{image}) {
		my $red;
		my $green;
		my $blue;
		my $tmp;
		# muss man das erst so zerlegen oder kann der alpha-Wert direkt beschrieben werden...
		my $fillcolor = Imager::Color->new(xname => $color);
		($red, $green, $blue, $tmp) = $fillcolor->rgba();
		$fillcolor->set($red, $green, $blue, $alpha);
#		print "  filling with color: ($red, $green, $blue, $alpha)\n";
		
		my $fill = Imager::Fill->new(solid => $fillcolor, combine => "normal");
		$hash->{image}->box(xmin => $x, ymin => $y, xmax => $x + $dx - 1, ymax => $y + $dy - 1, fill => $fill);
	}
}

sub SPI_CBerry28_Box3($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	
	my $x = $a[0];
	my $y = $a[1];
	my $dx = $a[2];
	my $dy = $a[3];
	my $border = $a[4];
	my $color = $a[5];
	
#	print "SPI_CBerry28_Box3:\n";

	if ($hash->{image}) {
		my $x1 = $x + $dx - 1;
		my $y1 = $y + $dy - 1;
		
		for my $i (0..$border-1) {
		#	print "SPI_CBerry28_Box3: ($x,$y)-($x1,$y1)\n";
			$hash->{image}->box(xmin => $x + $i, ymin => $y + $i, xmax => $x1 - $i, ymax => $y1 - $i, filled => 0, color => $color);
		}
	}
}

sub SPI_CBerry28_Box4($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	
	my $x = $a[0];
	my $y = $a[1];
	my $dx = $a[2];
	my $dy = $a[3];
	my $border = $a[4];
	my $color = $a[5];
	my $alpha = $a[6];
	
#	print "SPI_CBerry28_Box4:\n";

	if ($hash->{image}) {
		my $red;
		my $green;
		my $blue;
		my $tmp;
		# muss man das erst so zerlegen oder kann der alpha-Wert direkt beschrieben werden...
		my $fillcolor = Imager::Color->new(xname => $color);
		($red, $green, $blue, $tmp) = $fillcolor->rgba();
		$fillcolor->set($red, $green, $blue, $alpha);
#		print "  filling with color: ($red, $green, $blue, $alpha)\n";
		
		my $fill = Imager::Fill->new(solid => $fillcolor, combine => "normal");

		my $x1 = $x + $dx - 1;
		my $y1 = $y + $dy - 1;

		for my $i (0..$border-1) {
			$hash->{image}->box(xmin => $x + $i, ymin => $y + $i, xmax => $x1 - $i, ymax => $y1 - $i, fill => $fill);
		}
	}
}

sub SPI_CBerry28_SetFont($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $font = $a[0];
	my $size = $a[1];

	# TrueType-Fonts
	my $font_filename = '/usr/share/fonts/truetype/' . $font;

	$hash->{fontname} = $font;
	
	if(defined($fontlist{$font})) {
		$font_filename = '/usr/share/fonts/truetype/' . $fontlist{$font};
		$hash->{fontname} = $fontlist{$font};
	}
	
#	print "SPI_CBerry28_SetFont: $font $size\n";
	Log3 $name, 1, "SPI_CBerry28_SetFont: loading font $font_filename";
	
	$hash->{font} = Imager::Font->new(file => $font_filename);
	$hash->{fontSize} = $size;
	
	if (!$hash->{font}) {
#		print "SPI_CBerry28_SetFont: loading font failed! $font_filename\n";
		Log3 $name, 1, "SPI_CBerry28_SetFont: loading font failed! $font_filename";
	}
}

sub SPI_CBerry28_Text($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $x = $a[0];
	my $y = $a[1];
	my $color = $a[2];
	my $text = $a[3];
	
#	print "SPI_CBerry28_Text: ($x, $y) $text\n";
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_Text:' . $text;

	if ($hash->{image} && $hash->{font}) {
		eval {
			$hash->{font}->align(string => $text,
				size => $hash->{fontSize},
				color => $color,
				x => $x,
				y => $y,
				halign => 'left',
				valign => 'baseline',
				image => $hash->{image});
		} or do {
			my $e = $@;
	#		print "SPI_CBerry28_Text: exception $e\n";
			Log3 $name, 1, 'ERROR: SPI_CBerry28_Text: exception (' . $e . ')';
		}
	} else {
#		print "SPI_CBerry28_Text: No Font!\n";
		Log3 $name, 1, "SPI_CBerry28_Text: No Font!";
	}
}

sub SPI_CBerry28_SaveImage($$$)
{
	my ($hash, $filename, $type) = @_;
	my $name = $hash->{NAME};
	
#	print "SPI_CBerry28_SaveImage: $filename\n";

	if ($hash->{image}) {
		$hash->{image}->write(file=>$filename, type=>$type)
	}
}

sub SPI_CBerry28_SaveImageBmp($$)
{
	my ($hash, $filename, $type) = @_;
	my $name = $hash->{NAME};
	
#	print "SPI_CBerry28_SaveImage: $filename\n";

	if ($hash->{image}) {
		$hash->{image}->write(file=>$filename, type=>'bmp')
	}
}

sub SPI_CBerry28_SendImageToTFT($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	if (!defined($hash->{active})) {
		$hash->{active} = 0;
	}

	if ($hash->{image} && $hash->{active} == 0) {
		$hash->{active} = 1;
		
#		print "SPI_CBerry28_SendImageToTFT:\n";
		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SendImageToTFT:';
		
		# Reset RAM pointer ?
		SPI_CBerry28_WriteReg($hash, RAMWR);
	
		my $height = $hash->{image}->getheight;
		$height = DISPLAY_HEIGHT if $height > DISPLAY_HEIGHT;
		
		my $width = $hash->{image}->getwidth;
		$width = DISPLAY_WIDTH if $width > DISPLAY_WIDTH;

		if (CM_262K == 1) {
			$width *= 3;
		} else {
			$width *= 2;
		}

		# one scanline per transfer
		YLOOP: for my $y (0..$height-1) {
			my @colors = $hash->{image}->getscanline(y => $y);
			my @output = (length @colors);
			my $i = 0;
			
			for my $color (@colors) {
				my ($red, $green, $blue, $alpha) = $color->rgba;

				if (CM_262K == 1) {
					# 18bit/pixel
					# 262K-colors (RGB 6-6-6)
					$red = ($red >> 2) & 0x3F;
					$green = ($green >> 2) & 0x3F;
					$blue = ($blue >> 2) & 0x3F;
					
					my $word = ($red << 12) | ($green << 6) | ($blue);
					
					$output[$i] = ($word >> 16) & 0xFF;	$i++;
					$output[$i] = ($word >> 8) & 0xFF;	$i++;
					$output[$i] = $word & 0xFF;			$i++;

				} else {
					# 16bit/pixel
					# 65K-colors (RGB 5-6-5)
					$red = ($red >> 3) & 0x1F;
					$green = ($green >> 2) & 0x3F;
					$blue = ($blue >> 3) & 0x1F;
					
					my $word = ($red << 11) | ($green << 5) | ($blue);
					
					$output[$i] = ($word >> 8) & 0xFF;	$i++;
					$output[$i] = $word & 0xFF;			$i++;
				}
			}

			# limit pixels
			$i = $width if $i > $width;
		#	print "  line $y: length $i ($output[0], $output[1], $output[2], $output[3], $output[4], $output[5], $output[7], $output[8] ... $output[$i-2], $output[$i-1])\n";
		#	print "  line $y: length $i ($output[0], $output[1], $output[2], $output[3] ... $output[$i-4], $output[$i-3], $output[$i-2], $output[$i-1])\n";

			SPI_CBerry28_WriteMultiData($hash, $i, @output);
		}
		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SendImageToTFT: Done!';
		
		$hash->{active} = 0;
		
	} else {
		Log3 $name, 1, 'ERROR: SPI_CBerry28_SendImageToTFT: No Image or active!';
	}
}


1;

=pod
=begin html

<a name="I2C_TSL2561"></a>
<h3>I2C_TSL2561</h3>
<ul>
  <a name="I2C_TSL2561"></a>
  <p>
    With this module you can read values from the digital luminosity sensor TSL2561
    via the i2c bus on Raspberry Pi.<br><br>

    Before you can use the module on the Raspberry Pi you must load the I2C kernel
    modules.<br>
    Add these two lines to your <b>/etc/modules</b> file to load the kernel modules
    automatically when booting your Raspberry Pi.<br>
    <code><pre>
     i2c-bcm2708
     i2c-dev
    </pre></code>

    <b>Please note:</b><br>
    For the i2c communication, the perl modules HiPi::Device::I2C
    are required.<br>
    For a simple automated installation:<br>
    <code>wget http://raspberry.znix.com/hipifiles/hipi-install<br>
    perl hipi-install</code><br><br>

  <p>

  <b>Define</b>
  <ul>
    <code>define TSL2561 I2C_TSL2561 &lt;I2C device&gt; &lt;I2C address&gt</code><br>
    <br>
    Examples:
    <pre>
      define TSL2561 I2C_TSL2561 /dev/i2c-0 0x39
      attr TSL2561 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_TSL2561attr"></a>
  <b>Attributes</b>
  <ul>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the sensor for new measured
      values.<br>
      Default: 5, valid values: 1, 2, 5, 10, 20, 30<br><br>
    </li>
    <li>integrationTime<br>
      time in ms the sensor takes to measure the light.<br>
      Default: 13, valid values: 13, 101, 402
      see this <a href="https://learn.sparkfun.com/tutorials/tsl2561-luminosity-sensor-hookup-guide/using-the-arduino-library">tutorial</a>
      for more details
    </li>
    <li>gain<br>
      gain factor
      Default: 1, valid values: 1, 16
    </li>
    <li>autoGain<br>
      enable auto gain
      Default: 1, valid values: 0, 1
      if set to 1,the gain parameter is set automatically depending on light conditions
    </li>
</ul>
  <br>
</ul>


=end html

=cut
