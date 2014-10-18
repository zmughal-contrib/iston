package Iston::Drawable;
$Iston::Drawable::VERSION = '0.07';
use 5.12.0;

use Carp;
use Function::Parameters qw(:strict);
use Iston::Utils qw/identity as_oga/;
use Moo::Role;
use OpenGL qw(:all);

use aliased qw/Iston::Vector/;
use aliased qw/Iston::Vertex/;

# candidate for deletion
has rotation     => (is => 'rw', default => sub { [0, 0, 0] }, trigger => 1);
has enabled      => (is => 'rw', default => sub { 1 });
# candidate for deletion
has display_list => (is => 'ro', default => sub { 0 });

has center        => (is => 'lazy');
has boundaries    => (is => 'lazy');
has scale         => (is => 'rw', default => sub { 1; }, trigger => 1);
has vertices      => (is => 'rw', required => 0);
has indices       => (is => 'rw', required => 0);
has normals       => (is => 'rw', required => 0);
has texture       => (is => 'rw', clearer => 1);
has uv_mappings   => (is => 'rw', required => 0, clearer => 1);
has mode          => (is => 'rw', default => sub { 'normal' }, trigger => 1);
has default_color => (is => 'rw', default => sub { [1.0, 1.0, 1.0, 0.0] } );
has lighting      => (is => 'rw', default => sub { 1; });

has texture_id    => (is => 'lazy', clearer => 1);
has draw_function => (is => 'lazy', clearer => 1);

has shader                 => (is => 'rw', trigger => 1 );
has notifyer               => (is => 'rw', trigger => 1 );
has _uniform_for   => (is => 'ro', default => sub { {} } );
has _attribute_for => (is => 'ro', default => sub { {} } );

has _text_coords_oga => (is => 'lazy', clearer => 1);

# matrices
has model           => (is => 'rw', trigger => sub{ $_[0]->reset_model }, default => sub { identity; });
has model_translate => (is => 'rw', trigger => sub{ $_[0]->reset_model }, default => sub { identity; });
has model_scale     => (is => 'rw', trigger => sub{ $_[0]->reset_model }, default => sub { identity; });
has model_rotation  => (is => 'rw', trigger => sub{ $_[0]->reset_model }, default => sub { identity; });

has model_oga       => (is => 'lazy', clearer => 1);
has model_view_oga  => (is => 'lazy', clearer => 1);  # transpose (inverse( view * model))

# just cache
has _contexts => (is => 'rw', default => sub { {} });

requires 'has_texture';

method reset_model {
    $self->clear_model_oga;
    $self->clear_model_view_oga;
}

method _trigger_shader($shader) {
    for (qw/mytexture has_texture has_lighting default_color view_model/) {
        my $id = $shader->Map($_);
        croak "cannot map '$_' uniform" unless defined $id;
        $self->_uniform_for->{$_} = $id;
    }
    for (qw/texcoord coord3d N/) {
        my $id = $shader->MapAttr($_);
        croak "cannot map attribute '$_'" unless defined $id;
        $self->_attribute_for->{$_} = $id;
    }
}

method _trigger_notifyer($notifyer) {
    $notifyer->subscribe(view_change => sub { $self->clear_model_view_oga } );
}

method _trigger_rotation($values) {
    my $m = identity;
    for my $idx (0 .. @$values-1) {
        my $angle = $values->[$idx];
        if($angle) {
            my @axis_components = (0) x scalar(@$values);
            $axis_components[$idx] = 1;
            my $axis = Vector->new(\@axis_components);
            $m *= Iston::Utils::rotate($angle, $axis);
        }
    }
    $self->model_rotation($m);
}

method _trigger_scale($value) {
    $self->model_scale(Iston::Utils::scale($value));
}

sub _build_model_oga {
    my $self = shift;
    my $scale    = $self->model_scale;
    my $translate = $self->model_translate;
    my $rotation = $self->model_rotation;
    my $model = $self->model;
    my $matrix = $model * $rotation * $scale * $translate;
    $matrix = ~$matrix;
    return OpenGL::Array->new_list(GL_FLOAT, $matrix->as_list);
}

method _build_model_view_oga {
    my $scale    = $self->model_scale;
    my $translate = $self->model_translate;
    my $rotation = $self->model_rotation;
    my $model = $self->model * $rotation * $scale * $translate;
    my $view = $self->notifyer->last_value('view_change');
    my $matrix = (~($model * $view))->inverse;
    $matrix = ~$matrix;
    return OpenGL::Array->new_list(GL_FLOAT, $matrix->as_list);
}

# candidate for deletion
sub rotate {
    my ($self, $axis, $value) = @_;
    if (defined $value) {
        $self->rotation->[$axis] = $value;
        $self->_trigger_rotation($self->rotation);
    }
    else {
        return $self->rotation->[$axis];
    }
}

method reset_texture {
    $self->clear_texture;
    $self->clear_texture_id;
    $self->_clear_text_coords_oga;
    $self->clear_draw_function;
    $self->clear_uv_mappings;
}

method _trigger_mode {
    my $mode = $self->mode;
    if ($mode eq 'mesh') {
        $self->_contexts->{normal} = {
            indices => $self->indices,
        };
        $self->indices($self->_triangle_2_lines_indices);
    } else {
        $self->_contexts->{mesh} = {
            indices => $self->indices,
        };
        $self->indices($self->_contexts->{normal}->{indices});
    }
    $self->clear_draw_function;
};

method _triangle_2_lines_indices {
    my $source = $self->indices;
    my $components = 3;
    my @result = map {
        my $idx = $_;
        my @v = @{$source}[$idx*3 .. $idx*3+2];
        my @r = @v[0,1,1,2,2,0];
        @r;
    } (0 .. scalar(@$source) / $components-1);
    return \@result;
};

method _build_boundaries {
    my $first_vertex = $self->vertices->[0];
    my ($mins, $maxs) = map { Vertex->new($first_vertex) } (0 .. 1);
    my $vertices_count = scalar(@{$self->vertices});
    for my $vertex_index (0 .. $vertices_count-1) {
        my $v = $self->vertices->[$vertex_index];
        for my $c (0 .. 2) {
            $mins->[$c] = $v->[$c] if($mins->[$c] > $v->[$c]);
            $maxs->[$c] = $v->[$c] if($maxs->[$c] < $v->[$c]);
        }
    }
    return [$mins, $maxs];
};

method _build__text_coords_oga {
    my ($vbo_texcoords) = glGenBuffersARB_p(1);
    my $texcoords_oga = OpenGL::Array->new_list(
        GL_FLOAT, map { @$_ } @{ $self->uv_mappings }
    );
    $texcoords_oga->bind($vbo_texcoords);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $texcoords_oga, GL_STATIC_DRAW_ARB);
    return $texcoords_oga;
}

method _build_texture_id {
    croak("Generating texture for textureless object")
        unless $self->has_texture;

    my ($texture_id) = glGenTextures_p(1);

    my $texture = $self->texture;
    my $bpp = $texture->format->BytesPerPixel;
    my $rmask = $texture->format->Rmask;
    my $texture_format = $bpp == 4
        ? ($rmask == 0x000000ff ? GL_RGBA : GL_BGRA)
        : ($rmask == 0x000000ff ? GL_RGB  : GL_BGR );

    my($texture_width, $texture_height) = map { $texture->$_ } qw/w h/;

    glBindTexture(GL_TEXTURE_2D, $texture_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexImage2D_s(GL_TEXTURE_2D, 0, $texture_format, $texture_width, $texture_height,
                   0, $texture_format, GL_UNSIGNED_BYTE, ${ $texture->get_pixels_ptr });

    $self->clear_texture; # we do not need texture any more
    return $texture_id;
}

method _build_draw_function {
    my ($p_vertices, $p_normals) =
        map {
            my $v = $self->$_;
            croak "$_ is mandatory" if (!defined($v) or !@$v);
            $v;
        } qw/vertices normals/;
    my ($vertices, $normals) =
        map { as_oga($_) }
        ($p_vertices, $p_normals);
    my ($vbo_vertices, $vbo_normals) = glGenBuffersARB_p(2);

    $vertices->bind($vbo_vertices);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $vertices, GL_STATIC_DRAW_ARB);

    $normals->bind($vbo_normals);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $normals, GL_STATIC_DRAW_ARB);

    my $indices = $self->indices;
    my $indices_size = scalar(@$indices);
    my $mode = $self->mode;
    my $draw_mode = $mode eq 'normal'
        ? GL_TRIANGLES : GL_LINES;

    my $indices_oga =OpenGL::Array->new_list(
        GL_UNSIGNED_INT,
        @$indices
    );

    $self->shader->Enable;
    my $has_texture_u  = $self->_uniform_for->{has_texture };
    my $has_lighting_u = $self->_uniform_for->{has_lighting};
    my $my_texture_u   = $self->_uniform_for->{mytexture};
    my $view_model_u   = $self->_uniform_for->{view_model};

    my ($texture_id, $default_color);
    if ($self->has_texture) {
        $texture_id = $self->texture_id;
    } else {
        $default_color = $self->default_color;
    }

    my $attribute_texcoord = $self->_attribute_for->{texcoord};
    my $attribute_coord3d  = $self->_attribute_for->{coord3d };
    my $attribute_normal   = $self->_attribute_for->{N       };

    $self->shader->Disable;

    my $draw_function = sub {
        $self->shader->Enable;

        glUniform1iARB($has_lighting_u, $self->lighting);
        glUniform1iARB($has_texture_u, $self->has_texture);

        $self->shader->SetMatrix(model => $self->model_oga);
        $self->shader->SetMatrix(view_model => $self->model_view_oga);

        if (defined $texture_id) {
            glActiveTextureARB(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, $texture_id);
            glUniform1iARB($my_texture_u, 0); # /*GL_TEXTURE*/

            glEnableVertexAttribArrayARB($attribute_texcoord);
            glBindBufferARB(GL_ARRAY_BUFFER, $self->_text_coords_oga->bound);
            glVertexAttribPointerARB_c($attribute_texcoord, 2, GL_FLOAT, 0, 0, 0);
        } else {
            $self->shader->SetVector('default_color', @$default_color);
        }

        glEnableVertexAttribArrayARB($attribute_coord3d);
        glBindBufferARB(GL_ARRAY_BUFFER, $vertices->bound);
        glVertexAttribPointerARB_c($attribute_coord3d, 3, GL_FLOAT, 0, 0, 0);

        glEnableVertexAttribArrayARB($attribute_normal);
        glBindBufferARB(GL_ARRAY_BUFFER, $normals->bound);
        glVertexAttribPointerARB_c($attribute_normal, 3, GL_FLOAT, 0, 0, 0);

        glDrawElements_c(GL_TRIANGLES, $indices_size, GL_UNSIGNED_INT, $indices_oga->ptr);

        glDisableVertexAttribArrayARB($attribute_coord3d);
        glDisableVertexAttribArrayARB($attribute_texcoord) if (defined $texture_id);
        $self->shader->Disable;
    };
    return $draw_function;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Iston::Drawable

=head1 VERSION

version 0.07

=head1 AUTHOR

Ivan Baidakou <dmol@gmx.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Ivan Baidakou.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
