package Archive::SevenZip::API::ArchiveZip;
use strict;
use warnings;
use Carp qw(croak);
use Encode qw( decode encode );
use File::Basename qw(dirname basename);
use File::Copy;
use Archive::SevenZip 'AZ_OK';

our $VERSION= '0.20';

sub new {
    my( $class, %options )= @_;
    $options{ sevenZip } = Archive::SevenZip->new();
    bless \%options => $class;
};

sub sevenZip { $_[0]->{sevenZip} }

=head1 NAME

Archive::SevenZip::API::ArchiveZip - Archive::Zip compatibility API

=head1 SYNOPSIS

  my $ar = Archive::SevenZip->archiveZipApi(
      find => 1,
      archivename => $archivename,
      verbose => $verbose,
  );

This module implements just enough of the L<Archive::Zip>
API to pass some of the Archive::Zip test files. Ideally you can
use this API to enable a script that uses Archive::Zip
to also read other archive files supported by 7z.

=cut

# Helper to decode the hashref/named API
sub _params {
    my( $args, @names ) = @_;
    if( ref $args->[1] eq 'HASH' ) {
        return( $args->[0], @{ $args }{ @names } )
    } else {
        return @$args
    }
}

sub read {
    my( $self, $filename ) = _params(\@_, qw(filename));
    $self->sevenZip->{archivename} = $filename;
    return AZ_OK;
}

sub writeToFileNamed {
    my( $self, $targetName ) = _params(\@_, qw(fileName));

    my $source = $self->sevenZip->archive_or_temp;
    copy( $source, $targetName );
    return AZ_OK;
}

sub addFileOrDirectory {
    my($self, $name, $newName, $compressionLevel)
        = _params(\@_, qw(name zipName compressionLevel));
    $newName = $name
        unless defined $newName;
    $self->sevenZip->add(
        items => [ [$name, $newName] ],
        compression => $compressionLevel
    );
}

sub addString {
    my( $self, $content, $name, %options )
        = _params(\@_, qw( string zipName compressionLevel ));
    $self->sevenZip->add_scalar($name => $content);
    $self->memberNamed($name, %options);
}

sub addDirectory {
    # Create just a directory name
    my( $self, $name, $target, %options )
        = _params(\@_, qw( directoryName zipName ));
    $target ||= $name;

    $self->sevenZip->add_directory($name, $target, %options);
    $self->memberNamed($target, %options);
}

sub members {
    my( $self ) = @_;
    $self->sevenZip->members;
}

sub memberNames {
    my( $self ) = @_;
    map { $_->fileName } $self->sevenZip->members;
}

sub membersMatching {
    my( $self, $re, %options ) = @_;
    grep { $_->fileName =~ /$re/ } $self->sevenZip->members;
}

=head2 C<< $ar->numberOfMembers >>

  my $count = $az->numberOfMembers();

=cut

sub numberOfMembers {
    my( $self, %options ) = @_;
    my @m = $self->members( %options );
    0+@m
}

=head2 C<< $az->memberNamed >>

  my $entry = $az->memberNamed('hello_world.txt');
  print $entry->fileName, "\n";

=cut

# Archive::Zip API
sub memberNamed {
    #my( $self, $name, %options )
    my( $self, $name )
        = _params( \@_, qw( zipName ));
    #$self->sevenZip->memberNamed($name, %options );
    $self->sevenZip->memberNamed($name);
}

sub extractMember {
    #my( $self, $name, $target, %options ) = @_;
    my( $self, $name, $target )
        = _params(\@_, qw( memberOrZipName name ));
    if( ref $name and $name->can('fileName')) {
        $name = $name->fileName;
    };
    #$self->sevenZip->extractMember( $name, $target, %options );
    $self->sevenZip->extractMember( $name, $target );
}

sub removeMember {
    #my( $self, $name, $target, %options ) = @_;
    my( $self, $name )
        = _params( \@_, qw(memberOrZipName ));
    # Just for the result:
    my $res = ref $name ? $name : $self->memberNamed( $name );

    if( ref $name and $name->can('fileName')) {
        $name = $name->fileName;
    };
    #$self->sevenZip->removeMember( $name, %options );
    $self->sevenZip->removeMember( $name );

    $res
}

=head2 C<< $ar->replaceMember >>

  $ar->replaceMember('backup.txt', 'new-backup.txt');

Replaces the member in the archive. This is just delete then add.

I clearly don't understand the utility of this method. It clearly
does not update the content of one file with the content of another
file, as the name of the new file can be different.

=cut

# strikingly similar to Archive::Zip API
sub replaceMember {
    my( $self, $name, $replacement, %_options ) = @_;

    my %options = (%$self, %_options);

    if( $^O =~ /MSWin/ ) {
        $name =~ s!/!\\!g;
    }

    my $res = $self->removeMember( $name );
    $self->add( $replacement );

    $res
};


sub addFile {
    my( $self, $name, $target, $compressionLevel )
        = _params(\@_, qw(filename zipName compressionLevel ));
    if( ref $name and $name->can('fileName')) {
        $name = $name->fileName;
    };
    $target ||= $name;
    $self->sevenZip->add( items => [[ $name, $target ]]);
    return $self->memberNamed($target);
}

sub addMember {
    #my( $self, $name, $target, %options ) = @_;
    my( $self, $member ) = _param( \@_, qw(member));
    my $target = $member->fileName;
    my $fh = $member->open( binmode => ':raw' );
    local $/;
    my $content = <$fh>;
    $self->sevenZip->add_scalar( $target => $content );
    return $self->memberNamed($target );
}
{ no warnings 'once';
*add = \&addMember;
}

sub addTree {
    my( $self, $sourceDir, $target, $predicate, %options ) = @_;

    croak "Predicates are not supported, sorry"
        if $predicate;

    $target ||= $sourceDir;
    croak "Different target for ->addTree not supported, sorry"
        if $target ne $sourceDir;

    $self->sevenZip->add( items => [[ $sourceDir, $target ]], recursive => 1, %options );
    return $self->memberNamed($target, %options);
}
*add = \&addMember;

__END__

=head1 CAUTION

This module tries to mimic the API of L<Archive::Zip>.

=head2 Differences between Archive::Zip and Archive::SevenZip

=head3 7-Zip does not guarantee the order of entries within an archive

The Archive::Zip test suite assumes that items added later to an
archive will appear later in the directory listing. 7-zip makes no
such guarantee.

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/archive-sevenzip>.

=head1 SUPPORT

The public support forum of this module is
L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Archive-SevenZip>
or via mail to L<archive-sevenzip-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2015-2024 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
