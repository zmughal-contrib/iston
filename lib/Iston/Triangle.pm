package Iston::Triangle;

use 5.12.0;

use Carp;
use Function::Parameters qw(:strict);
use Iston::Vector;
use List::MoreUtils qw/pairwise/;
use Moo;

use aliased qw/Iston::Triangle/;
use aliased qw/Iston::Vector/;
use aliased qw/Iston::Vertex/;

has vertices => (is => 'rw', required => 1, isa =>
    sub {
        die "Triangle should have exactly 3 vertices"
            unless @{$_[0]} == 3;
    }
);

has normal => (is => 'lazy');

method _build_normal {
    return Iston::Vector::normal($self->vertices, [0 .. 2]);
}

method subdivide {
    my @vertex_pairs = (
        [ [0, 1], [0, 2] ],
        [ [1, 0], [1, 2] ],
        [ [2, 0], [2, 1] ],
    );
    my @mediate_vectors = map {
        my ($A, $B) = map {
            my ($v1, $v2) = map { $self->vertices->[$_] } @$_;
            my @vector = pairwise { $b - $a } @$v1, @$v2;
            #$v1->vector_to($v2);
            \@vector;
        } @$_;
        my @values = pairwise { ($a + $b)/2 } @$A, @$B;
        \@values;
        #Iston::Vector->new(\@values);
    } @vertex_pairs;
    my @new_vertices = map {
        my $vector = $mediate_vectors[$_];
        my $base_vertex = $self->vertices->[ $vertex_pairs[$_]->[0]->[0] ];
        # move vector to at the base vertex
        my @values = pairwise { $a + $b } @$vector, @$base_vertex;
        Iston::Vertex->new(\@values);
    } (0 .. 2);
    my @new_triangles = map {
        Triangle->new(vertices => $_)
    }(
        # reserve vertices traverse order
        [$self->vertices->[0], $new_vertices[2], $new_vertices[1]],
        [$self->vertices->[1], $new_vertices[0], $new_vertices[2]],
        [$self->vertices->[2], $new_vertices[1], $new_vertices[0]],
        [$new_vertices[2], $new_vertices[0], $new_vertices[1]],
    );
    return \@new_triangles;
};

1;