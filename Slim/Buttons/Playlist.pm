package Slim::Buttons::Playlist;

# $Id: Playlist.pm,v 1.37 2004/11/19 04:04:24 kdf Exp $

# Slim Server Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Browse;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

Slim::Buttons::Common::addMode('playlist',getFunctions(),\&setMode);

# Each button on the remote has a function:

my %functions = (
	'playdisp' => sub {
		# toggle display mod for now playing...
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $pdm = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");
		unless (defined $pdm) { $pdm = 1; };
		unless (defined $buttonarg) { $buttonarg = 'toggle'; };
		if ($button eq 'playdisp_toggle') {
			my $playlistlen = Slim::Player::Playlist::count($client);
			# playingDisplayModes are
			# 0 show nothing
			# 1 show elapsed time
			# 2 show remaining time
			# 3 show progress bar
			# 4 show elapsed time and progress bar
			# 5 show remaining time and progress bar
			if (($playlistlen > 0) && (showingNowPlaying($client))) {
				$pdm = ($pdm + 1) % (Slim::Utils::Prefs::clientGet($client,'showbufferfullness') ? 7 : 6);
			} elsif ($playlistlen > 0) {
				browseplaylistindex($client,Slim::Player::Source::currentSongIndex($client));
			}
		} else {
			if ($buttonarg =~ /[0-5]$/) {
				$pdm = $buttonarg;
			}
		}
		Slim::Buttons::Common::param($client,'animateTop',$pdm);
		Slim::Utils::Prefs::clientSet($client, "playingDisplayMode", $pdm);
		$client->update();
	},
	'up' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my($songcount) = Slim::Player::Playlist::count($client);
		if ($songcount < 2) {
			$client->bumpUp();
		} else {
			$inc = ($inc =~ /\D/) ? -1 : -$inc;
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
			browseplaylistindex($client, $newposition);
			$client->update();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my($songcount) = Slim::Player::Playlist::count($client);
		if ($songcount < 2) {
			$client->bumpDown();
		} else {
			if ($inc =~ /\D/) {$inc = 1}
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
			browseplaylistindex($client,$newposition);
			$client->update();
		}
	},
	'left' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Home::jump($client, 'NOW_PLAYING');
		Slim::Buttons::Common::setMode($client, 'home');
		$client->pushRight(\@oldlines, [Slim::Display::Display::curLines($client)]);
	},
	'right' => sub  {
		my $client = shift;
		my $playlistlen = Slim::Player::Playlist::count($client);
		if ($playlistlen < 1) {
			$client->bumpRight();
		} else {
			my @oldlines = Slim::Display::Display::curLines($client);
			Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => Slim::Player::Playlist::song($client, browseplaylistindex($client))
																	,'current' => browseplaylistindex($client) == Slim::Player::Source::currentSongIndex($client)} );
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $newposition;
		# do an unsorted jump
		$newposition = Slim::Buttons::Common::numberScroll($client, $digit, Slim::Player::Playlist::shuffleList($client), 0);
		browseplaylistindex($client,$newposition);
		$client->update();	
	},
	'add' => sub  {
		my $client = shift;
		if (Slim::Player::Playlist::count($client) > 0) {
			# rec button deletes an entry if you are browsing the playlist...
			my $songtitle = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, browseplaylistindex($client)));
			Slim::Control::Command::execute($client, ["playlist", "delete", browseplaylistindex($client)]);	
			$client->showBriefly(
					string('REMOVING_FROM_PLAYLIST'), 
					$songtitle, undef, 1);
		}
	},
	
 	'zap' => sub {
 		my $client = shift;
 		my $zapped=catfile(Slim::Utils::Prefs::get('playlistdir'), string('ZAPPED_SONGS') . '.m3u');
		if (Slim::Player::Playlist::count($client) > 0) {
			$client->showBriefly(
					string('ZAPPING_FROM_PLAYLIST'),
					Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, browseplaylistindex($client))), undef, 1);
			Slim::Control::Command::execute($client, ["playlist", "zap", browseplaylistindex($client)]);
		}
	},

	'play' => sub  {
		my $client = shift;
		if (showingNowPlaying($client)) {
			if (Slim::Player::Source::playmode($client) eq 'pause') {
				Slim::Control::Command::execute($client, ["pause"]);
			} elsif (Slim::Player::Source::rate($client) != 1) {
				Slim::Control::Command::execute($client, ["rate", 1]);
			} else {
				Slim::Control::Command::execute($client, ["playlist", "jump", browseplaylistindex($client)]);
			}	
		} else {
			Slim::Control::Command::execute($client, ["playlist", "jump", browseplaylistindex($client)]);
		}
		$client->update();
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $how = shift;
	$client->lines(\&lines);
	if ($how ne 'pop') { jump($client); }
}

sub jump {
	my $client = shift;
	my $pos = shift;
	if (Slim::Buttons::Common::mode($client) eq 'playlist') {
		if (!defined($pos)) { 
			$pos = Slim::Player::Source::currentSongIndex($client);
		}
		browseplaylistindex($client,$pos);
	}
}

#
# Display the playlist browser
#		
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay2);

	if (showingNowPlaying($client) || (Slim::Player::Playlist::count($client) < 1)) {
		return $client->currentSongLines();
	} else {
		if ( browseplaylistindex($client) + 1 > Slim::Player::Playlist::count($client)) {
			browseplaylistindex($client,Slim::Player::Playlist::count($client)-1)
		}
		$line1 = sprintf "%s (%d %s %d) ", string('PLAYLIST'), browseplaylistindex($client) + 1, string('OUT_OF'), Slim::Player::Playlist::count($client);
		$line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, browseplaylistindex($client)));
		$overlay2 = Slim::Display::Display::symbol('notesymbol');
		return ($line1, $line2, undef, $overlay2);
	}
}

# this is somewhat confusing.
sub showingNowPlaying {
	my $client = shift;
	return (
		(Slim::Buttons::Common::mode($client) eq 'screensaver') || 
		(Slim::Buttons::Common::mode($client) eq 'playlist') && 
			(browseplaylistindex($client) == Slim::Player::Source::currentSongIndex($client))
	);
}

sub browseplaylistindex {
	my $client = shift;
	my $playlistindex = shift;
	
	# get (and optionally set) the browseplaylistindex parameter that's kept in param stack
	return Slim::Buttons::Common::param($client, 'browseplaylistindex', $playlistindex);
}

# DEPRECATED: for compatibility only, use $client->nowPlayingModeLines();
sub nowPlayingModeLines {
	shift->nowPlayingModeLines(shift);
}
1;

__END__
