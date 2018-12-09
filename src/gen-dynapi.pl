#!/usr/bin/perl -w
# generate c structs/arrays for all dwg objects and its fields for a dynamic API.
# -> name, type, offset
# linear search is good enough.
# This is needed for in_dxf, dwgfilter,
# a maintainable and shorter dwg_api and shorter language bindings.

#dwg.h:
# typedef struct _dwg_header_variables
# typedef struct _dwg_entity_(.*)
# typedef struct _dwg_object_(.*)
#subtypes:
# typedef struct _dwg_TYPE_subtype

use strict;
use warnings;
use vars qw(@entity_names @object_names @subtypes);
use Convert::Binary::C;
#use Data::Dumper;
BEGIN { chdir 'src' if $0 =~ /src/; }
my $c = Convert::Binary::C->new->Include(".")->Define('HAVE_CONFIG_H');
my $hdr = "../include/dwg.h";
$c->parse_file($hdr);

#print Data::Dumper->Dump([$c->struct('_dwg_entity_TEXT')], ['_dwg_entity_TEXT']);
#print Data::Dumper->Dump([$c->struct('struct _dwg_header_variables')], ['Dwg_Header_Variables']);

local (@entity_names, @object_names, @subtypes);
# todo: harmonize more subtypes
for (sort $c->struct_names) {
  if (/_dwg_entity_([A-Z0-9_]+)/) {
    push @entity_names, $1;
  } elsif (/_dwg_object_([A-Z0-9_]+)/) {
    push @object_names, $1;
  } elsif (/_dwg_header_variables/) {
    ;
  } elsif (/_dwg_([A-Z0-9]+)(_|$)/) {
    push @subtypes, $_;
  } else {
    #print " (?)";
  }
}
# todo: get BITCODE_ macro types for each struct field
my (%h, $n);
open my $in, "<", $hdr or die;
while (<$in>) {
  if (!$n) {
    if (/^typedef struct (_dwg_.+) \{/) {
      $n = $1;
    } elsif (/^typedef struct (_dwg_\S+)$/) {
      $n = $1;
    }
  } elsif (/^\}/) { # close the struct
    $n = '';
  } elsif (/^ +BITCODE_(.+) (\w.*);/) {
    $h{$n}{$2} = $1;
  }
}
close $in;

open my $fh, ">dynapi.c" or die;

sub out_struct {
  my ($tmpl, $n) = @_;
  my $s = $c->struct($tmpl);
  #print $fh " /* ", Data::Dumper->Dump([$s], [$n]), "*/\n";
  $n = "_dwg_$n" unless $n =~ /^_dwg_/;
  print $fh "/* from typedef $tmpl: */\n",
    "struct _name_type_offset $n","_fields[] = {\n";
  for my $d (@{$s->{declarations}}) {
    my $type = $d->{type};
    my $decl = $d->{declarators}->[0];
    my $name = $decl->{declarator};
    $name =~ s/^\*//g;
    # unexpand BITCODE_ macros: e.g. unsigned int -> BITCODE_BL
    my $s = $tmpl;
    $s =~ s/^struct //;
    my $bc = exists $h{$s} ? $h{$s}{$name} : undef;
    $type = $bc if $bc;
    # TODO: DIMENSION_COMMON, _3DSOLID_FIELDS macros
    if ($type =~ /\b(unsigned|char|int|long|double)\b/) {
      warn "unexpanded $type $n.$name\n";
    }
    if ($type =~ /^HASH\(/) { # inlined struct or union
      warn "inlined type $type  $n.$name";
      #$type = $type->{type}; # size.width, size.height
    }
    printf $fh "  { \"%s\", \"%s\", OFF(%s,%s, %d) },\n",
      $name, $type, $tmpl,$name,$decl->{offset};
  }
  print $fh "};\n";
}

for (<DATA>) {
  # expand enum or struct
  if (/\@\@(\w+ \w+)\@\@/) {
    my $tmpl = $1;
    if ($tmpl =~ /^enum (\w+)/) {
      my $s = $c->enum($tmpl);
      #print $fh "\n/* ";
      #print $fh Data::Dumper->Dump([$s], [$1]);
      #print $fh "\n*/";
      my $i = 0;
      for (sort keys %{$s->{enumerators}}) {
        my ($k,$v) = ($_, $s->{enumerators}->{$_});
        $k =~ s/^DWG_TYPE_//;
        printf $fh "  { \"%s\", %d },\t/* %d */\n", $k, $v, $i++;
      }
    } elsif ($tmpl =~ /^list (\w+)/) {
      no strict 'refs';
      my $i = 0;
      for (@{$1}) {
        printf $fh "  \"%s\",\t/* %d */\n", $_, $i++;
      }
    } elsif ($tmpl =~ /^for dwg_entity_ENTITY/) {
      for (@entity_names) {
        out_struct("struct _dwg_entity_$_", $_);
      }
    } elsif ($tmpl =~ /^for dwg_object_OBJECT/) {
      for (@object_names) {
        out_struct("struct _dwg_object_$_", $_);
      }
    } elsif ($tmpl =~ /^for dwg_subtypes/) {
      for (@subtypes) {
        out_struct("struct $_", $_);
      }
    } elsif ($tmpl =~ /^struct _dwg_(\w+)/) {
      out_struct($tmpl, $1);
    }
  } else {
    print $fh $_;
  }
}
close $fh;

__DATA__
/* ex: set ro ft=c: -*- mode: c; buffer-read-only: t -*-
   generated by gen-dynapi.pl from include/dwg.h, do not modify. */

#include "dynapi.h"

struct _name_type {
  const char *const name;
  int type;
};

/* from enum DWG_OBJECT_TYPE: */
const struct _name_type dwg_name_types[] = {
  @@enum DWG_OBJECT_TYPE@@
};

/* from typedef struct _dwg_entity_*: */
const char *const dwg_entity_names[] = {
  @@list entity_names@@
};
/* from typedef struct _dwg_object_*: */
const char *const dwg_object_names[] = {
  @@list object_names@@
};

struct _name_type_offset {
  const char *const name;
  const char *const type;
  int offset;
};

@@struct _dwg_header_variables@@
@@for dwg_entity_ENTITY@@
@@for dwg_object_OBJECT@@
@@for dwg_subtypes@@