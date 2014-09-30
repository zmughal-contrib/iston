package Iston::Object;
$Iston::Object::VERSION = '0.07';
use 5.16.0;

use Carp;
use Iston::Matrix;
use Iston::Utils qw/generate_list_id identity/;
use Moo;
use List::Util qw/max/;
use Function::Parameters qw(:strict);
use OpenGL qw(:all);
use OpenGL::Image;

use aliased qw/Iston::Vertex/;

with('Iston::Drawable');

has texture_file => (is => 'rw', required => 0, predicate => 1);

method BUILD {
    if ($self->has_texture_file && !$ENV{ISTON_HEADLESS}) {
        my $texture = OpenGL::Image->new( source => $self->texture_file );
        croak("texture isn't power of 2?") if (!$texture->IsPowerOf2());
        $self->texture($texture);
    }
};

method _build_center {
    my ($v_size, $n_size) = map { scalar(@{ $self->$_ }) }
        qw/vertices normals/;
    croak "Count of vertices must match count of normals"
        unless $v_size == $n_size;

    my($mins, $maxs) = map { $self->boundaries->[$_] } (0, 1);
    my @avgs = map { ($mins->[$_] + $maxs->[$_]) /2  } (0 .. 2);
    return Vertex->new(\@avgs);
};

method radius {
    my $c = $self->center;
    my $r = max(
        map { $_->length }
        map { $c->vector_to($_) }
        @{ $self->vertices }
    );
    $r;
}



1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Iston::Object

=head1 VERSION

version 0.07

=head1 AUTHOR

Ivan Baidakou <dmol@gmx.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Ivan Baidakou.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
