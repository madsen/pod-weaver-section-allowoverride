#---------------------------------------------------------------------
package Pod::Weaver::Section::AllowOverride;
#
# Copyright 2012 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: 31 May 2012
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: Allow POD to override a Pod::Weaver-provided section
#---------------------------------------------------------------------

use 5.010;
use Moose;
with qw(Pod::Weaver::Role::Transformer Pod::Weaver::Role::Section);

our $VERSION = '0.05';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

use namespace::autoclean;
use Moose::Util::TypeConstraints;
use Pod::Elemental::MakeSelector qw(make_selector);

#=====================================================================

=attr header_re

This regular expression is used to select the section you want to
override.  It's matched against the section name from the C<=head1>
line.  The default is an exact match with the name of this plugin.
(e.g. if the plugin name is AUTHOR, the default would be C<^AUTHOR$>)

=cut

has header_re => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {'^' . quotemeta(shift->plugin_name) . '$' },
);

=attr action

This controls what to do when both a Pod::Weaver-provided section and
a POD-provided section are found.  It must be one of the following values:

=begin :list

= replace
Replace the Pod::Weaver-provided section with the POD-provided one.
(This is the default.)

= prepend
Place the POD-provided section at the beginning of the
Pod::Weaver-provided one.  The POD-provided header is used, and the
Pod::Weaver-provided header is discarded.

= append
Place the POD-provided section at the end of the
Pod::Weaver-provided one.  The POD-provided header is used, and the
Pod::Weaver-provided header is discarded.

=end :list

=cut

has action => (
  is  => 'ro',
  isa => enum([ qw(replace prepend append) ]),
  default => 'replace',
);

=attr match_anywhere

By default, AllowOverride must immediately follow the section to be
overriden in your F<weaver.ini>.  If you set C<match_anywhere> to a
true value, then it can come anywhere after the section to be
overriden (i.e. there can be other sections in between).
AllowOverride will search backwards for a section matching
C<header_re>, and die if there is no such section.

This is useful if the section you want to override comes from a bundle.

=cut

has match_anywhere => (
  is  => 'ro',
  isa => 'Bool',
  default => 0,
);

has _override_with => (
  is   => 'rw',
  does => 'Pod::Elemental::Node',
);

#---------------------------------------------------------------------
# Return a sub that matches a node against header_re:

has _section_matcher => (
  is   => 'ro',
  isa  => 'CodeRef',
  lazy => 1,
  builder  => '_build_section_matcher',
  init_arg => undef,
);

sub _build_section_matcher
{
  my $self = shift;

  my $header_re = $self->header_re;

  return make_selector(qw(-command head1  -content) => qr/$header_re/);
} # end _build_section_matcher

#---------------------------------------------------------------------
# Look for a matching section in the original POD, and remove it temporarily:

sub transform_document
{
  my ($self, $document) = @_;

  my $match    = $self->_section_matcher;
  my $children = $document->children;

  for my $i (0 .. $#$children) {
    if ($match->( $children->[$i] )) {
      # Found matching section.  Store & remove it:
      $self->_override_with( splice @$children, $i, 1 );
      last;
    } # end if this is the section we're looking for
  } # end for $i indexing @$children
} # end transform_document

#---------------------------------------------------------------------
# If we found a section in the original POD,
# use it instead of the one now in the document:

sub weave_section
{
  my ($self, $document, $input) = @_;

  my $override = $self->_override_with;
  return unless $override;

  my $section_matcher = $self->_section_matcher;
  my $children = $document->children;
  my $prev;

  if ($self->match_anywhere) {
    my $pos = @$children;
    while (1) {
      $self->log_fatal(["No section matching /%s/", $self->header_re])
          unless $pos--;
      last if $section_matcher->( $children->[$pos] );
    }
    $prev = splice @$children, $pos, 1, $override;
  } else {
    if (@$children and $section_matcher->( $children->[-1] )) {
      $prev = pop @$children;
    } else {
      $self->log(["The previous section did not match /%s/, won't override it",
                  $self->header_re]);
    }

    push @$children, $override;
  } # end else must override immediately preceding section

  for my $action ($self->action) {
    last if $action eq 'replace' or not $prev; # nothing more to do

    my $prev_content = $prev->children;

    if (     $action eq 'prepend') {
      push    @{ $override->children }, @$prev_content
    } elsif ($action eq 'append')  {
      unshift @{ $override->children }, @$prev_content
    }
  } # end for $self->action
} # end weave_section

#=====================================================================
# Package Return Value:

__PACKAGE__->meta->make_immutable;
1;

=head1 SYNOPSIS

  [Authors]
  [AllowOverride]
  header_re = ^AUTHORS?$
  action    = replace ; this is the default
  match_anywhere = 0  ; this is the default

=head1 DESCRIPTION

Sometimes, you might want to override a normally-generic section in
one of your modules.  This section plugin replaces the preceding
section with the corresponding section taken from your POD (if it
exists).  If your POD doesn't contain a matching section, then the
Pod::Weaver-provided one will be used.

Both the original section in your POD and the section provided by
Pod::Weaver must match the C<header_re>.  Also, this plugin must
immediately follow the section you want to replace (unless you set
C<match_anywhere> to a true value).

It's a similar idea to L<Pod::Weaver::Role::SectionReplacer>, except
that it works the other way around.  SectionReplacer replaces the
section from your POD with a section provided by Pod::Weaver.

=head1 SEE ALSO

L<Pod::Weaver::Role::SectionReplacer>,
L<Pod::Weaver::PluginBundle::ReplaceBoilerplate>

=for Pod::Coverage
transform_document
weave_section
