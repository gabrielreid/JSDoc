package JSDoc;

=head1 NAME

JSDoc - parse JavaScript source file for JSDoc comments

=head1 SYNOPSIS
    
    parse_jsdoc_source(\$js_source, \&print_comment);
    
    sub print_comment {
        my($obj_name, $type, $code, $comment_ref) = @_;
        my %comment = %{$comment_ref};
        print "$obj_name $type\n";
        print "$code\n";
        if ($comment{summary}) {
            print "summary: $comment{summary}\n";
        }
        if ($comment{args}) {
            my %args = %{$comment{args}};
            foreach (keys %args) {
                print "$_: $args{$_}\n";
            }
        }
        if ($comment{vars}) {
            my %vars = %{$comment{vars}};
            foreach (keys %vars) {
                print "$_: ".join(", ", @{$vars{$_}})."\n";
            }
        }
    }
    
=head1 DESCRIPTION

The C<parse_jsdoc_source> function requires a ref to string holding the 
source code of a javascript object file, and a ref to a callback subroutine 
to handle any found JSDoc elements. The source file is parsed and the 
callback is called as each element is found.

The C<parse_code_tree> function requires a ref to a string holding the
souce code of a javascript object file or files. It returns a data structure
that describes the object hierarchy contained in the source file, as well
as included documentation for all fields and methods. The resulting
data structure has the following form (for each class):

   Class
      |
      +- constructor_args
      |
      +- extends  
      |
      +- constructor_summary
      |
      +- class_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- args
      |  |  |
      |  |  +- vardescrip
      |  |  |
      |  |  +- varname
      |  |
      |  +- returns
      |
      +- instance_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- args
      |  |  |
      |  |  +- vardescrip
      |  |  |
      |  |  +- varname
      |  |
      |  +- returns
      | 
      +- class_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name
      |
      +- instance_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name

      |
      +- inherits
         |
         +- Class
            |
            +- instance_fields
            |
            +- instance_methods

=head1 AUTHOR

mmathews@jscan.org
Gabriel Reid gab_reid@users.sourceforge.net

=cut

require 5.000;
use Carp;
use Exporter;

use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(parse_jsdoc_source parse_code_tree);

use vars qw/ %CLASSES %FUNCTIONS /;

sub parse_jsdoc_source {

#params:
    # a reference to a scalar, the js object source code
    my $js_src = ${$_[0]};
    # a reference to a sub, used as a callback
    my $handle_comment = $_[1];
    
    # perlify os line-endings
    $js_src =~ s/(\r\n|\r)/\n/g;
    
    while ($js_src =~ m!
                            /\*\*         # the start of a JSDoc comment
                            (.*?)         # everything within that comment
                            \*/           # the end of a JSDoc comment
                            \s*\n\s*      # possible whitespace and a newline
                            (.*?)         # everything on the following line
                            (\n|;|//)     # up to one of these statement terminators
                       !gsx) {



        # grab the contents of a doc-comment and the line of code that follows
        my ($doc, $code) = ($1, $2);

        # trim leading whitespace and asterisks from doc-comment
        $doc =~ s/^[\t \*]*//gm;
        
        # is the code a constructor def? like this:
        # ObjectName = function(arg, arg) {
        # function ObjectName(arg, arg) {
        if ($code =~ m!^\s*([A-Z]\w*)\s*=\s*function\s*(\(.*?\))\w*\{?!
        or $code =~ m!^\s*function\s+([A-Z]\w*)\s*(\(.*?\))\w*\{?!) {
            &$handle_comment($1, "CONSTRUCTOR", "new $1$2", parse_jsdoc_comment($doc));
        }
        
        # is the code a property def? like this:
        # ObjectName.prototype.property = function(arg, arg)
        # ObjectName.prototype.property = "value"
        if ($code =~ m!^\s*([A-Z]\w*)\.prototype\.(\w+)(\s*=\s*function\s*(\(.*?\)))?!) {
            if ($4) {
                &$handle_comment($1, "METHOD", "$1.$2$4", parse_jsdoc_comment($doc));
            }
            else {
                &$handle_comment($1, "PROPERTY", "$1.$2", parse_jsdoc_comment($doc));
            }
        }

    }
}

sub parse_jsdoc_comment {
    my $doc = shift;

    # remember each part that is parsed
    my %parsed = ();
    
    # the first paragraph could be a summary statement
    # a paragraph may follow of variable defs (variable names start with "@")
    my ($summary, $variable_str) = $doc =~ /^\s*([^@].*?)\s*(?:\n\n\s*(.*)\s*)?$/gs;
    
    $parsed{summary} = $summary;

    # two types of variable def can be dealt with here:
    # a @argument has a two-part value -- the arg name and a description
    # all other @<variables> only have a single value each (although there may
    # be many variables with the same name)
    if($variable_str) {
        my %args = ();
        my %vars = ();
        while ($variable_str =~ /(?:^|\s*\n)\@argument\s+(\w+)\s+(\S.*?)(?=\n\n|\n@|$)/gs) {
            $args{$1} = $2;
        }
        $parsed{args} = \%args;

        while ($variable_str =~ /(?:^|\s*\n)\@(?!argument)(\w+)\s+(\S.*?)(?=\n\n|\n@|$)/gs) {
            $vars{$1} = [] unless defined $vars{$1};
            push(@{$vars{$1}}, $2);
        }
        $parsed{vars} = \%vars;
    }
    return \%parsed;
}


#
# Public function that returns a datastructure representing the JS classes
# and their documentation
#
sub parse_code_tree {
   my $js_src = ${$_[0]};

   # perlify os line-endings
   $js_src =~ s/(\r\n|\r)/\n/g;

   # clear out all big block comments without related code
   $js_src =~ s/\/\*\*([^\/]|([^*]\/))*\*\/\s*\n\s*\n//sg;

   &fetch_funcs_and_classes($js_src);

   &map_all_properties();

   &build_class_hierarchy(); 

   &set_class_constructors();

   for my $class(values %CLASSES){
      delete $class->{_class_properties};
      delete $class->{_instance_properties};
   }
   
   return \%CLASSES;
}

#
# This is just an altered version of the original implementation because
# I encountered some problems with that one, but don't want to break anything
# that is based on it
# PARAM: The document string to be parsed
#
sub parse_jsdoc_comment2 {
   my $doc = shift;
  
   $doc =~ s/^\s*\*//gm;

   # remember each part that is parsed
   my %parsed = ();
   
   # the first paragraph could be a summary statement
   # a paragraph may follow of variable defs (variable names start with "@")
   my ($summary, $variable_str) = $doc =~ /^\s*(.*?)\s*(@.*)?$/gxs;

   $parsed{summary} = $summary;


   # two types of variable def can be dealt with here:
   # a @argument has a two-part value -- the arg name and a description
   # all other @<variables> only have a single value each (although there may
   # be many variables with the same name)
   if($variable_str) {
       my %args = ();
       my %vars = ();
       while ($variable_str =~ /\@(?:param|argument)\s+(\w+)\s+([^\@]*)/gs) {
          $args{$1} = $2;
       }
       $parsed{args} = \%args;
       while ($variable_str =~ /\@(\w+)([^\@]*)/gs) {
           my ($name, $val) = ($1, $2);
           next if $name eq 'param' || $name eq 'argument';
           $name =~ s/^return$/returns/; # Allow returns and return to be used
           $vars{$name} = [] unless defined $vars{$name};
           push(@{$vars{$name}}, $val);
       }
       $parsed{vars} = \%vars;
   }
   return \%parsed;
}

#
# Builds up the global FUNCTION and CLASSES hashes
# with the names of functions and classes
#
sub fetch_funcs_and_classes {
   my $js_src = shift;
    
   while ($js_src =~ m!
         (?:/\*\*(.*?)\*/\s*\n\s*)?                   # Documentation
         (?:(?:function\s*(\w+)\s*(\(.*?\))\s*\{)|         # Function
         (?:(\w+)(\.prototype)?\.(\w+)\s*=\s*function\s*(\(.*?\)))| # Anonymous function 
         (?:(\w+)\.prototype\.(\w+)\s*=\s*(.*?);)|    # Instance property 
         (?:(\w+)\.prototype\s*=\s*new\s*(\w+)\(.*?\)\s*;)| #Inheritance
         (?:(\w+)\.(\w+)\s*=\s*(.*?);))        # Class property
      !gsx){

      my $doc;
      $doc = $1 or $doc = "";

      if ($2){
         my ($func, $arglist, $post) = ($2, $3, $');
         &add_function($doc, $func, $arglist);
         if ($doc =~ /\@constructor/){
            $js_src = &evaluate_constructor($doc, $func, $arglist, $post);
         }
      } elsif ($4 && $6 && $FUNCTIONS{$4}){
         &add_anonymous_function($doc, $4, $6, $7, not defined($5));
      } elsif ($8 && $9 && defined($10)) {
         &add_property($doc, $8, $9, $10, 0);
      } elsif ($11 && $12){
         &set_base_class($11, $12);
      } elsif ($13 && $14 && $15 && $14 ne 'prototype' 
         && $13 ne 'this' && $FUNCTIONS{$13}){
            &add_property($doc, $13, $14, $15, 1);
      }
   }
}

#
# Add a function that is given as Class.prototype.blah = function(){...}
#
sub add_anonymous_function {
   my ($doc, $class, $function_name, $arg_list, $is_class_prop) = @_;
   &add_class($class);
   my $fake_name = "__$class.$function_name";
   my $is_private = $function_name =~ s/^__________//;
   &add_function($doc, $fake_name, $arg_list, $is_private);
   &add_property($doc, $class, $function_name, $fake_name, $is_class_prop);
}


# 
# Add a class to the global CLASSES hash
#
sub add_class {
   my $class = shift;
   if (!$CLASSES{$class}){
      $CLASSES{$class} = {};
      $CLASSES{$class}->{instance_fields} = [];
      $CLASSES{$class}->{class_fields} = [];
      $CLASSES{$class}->{instance_methods} = [];
      $CLASSES{$class}->{class_methods} = [];
   }
}

#
# Set the base class for a given class
#
sub set_base_class {
   my ($class, $base_class) = @_;
   &add_class($class);
   $CLASSES{$class}->{extends} = $base_class;
}

#
# Add a property, either a class or instance method or field
#
sub add_property {
   my ($doc, $class, $property, $value, $is_class_property) = @_;

   &add_class($class);
   $doc =~ s/^[\t \*]*//gm;
   my $key = $is_class_property ? '_class_properties' : '_instance_properties';
   push @{$CLASSES{$class}->{$key}}, 
      {
	 property_doc => $doc,
	 property_name => $property,
	 property_value => $value
      };

}


#
# Add a function and its documentation to the global FUNCTION hash
#
sub add_function {
   my ($doc, $function, $arg_list, $is_private) = @_;
   if ($FUNCTIONS{$function}){
      warn "Function $function already declared\n";
   }
   $FUNCTIONS{$function} = {};
   my $func = $FUNCTIONS{$function};
   $arg_list and $func->{argument_list} = join(" ", split("\\s+", $arg_list))
      or $func->{argument_list} = "()";
    
   my $documentation = parse_jsdoc_comment2($doc);
   my $function_ref = $FUNCTIONS{$function};
   
   $function_ref->{is_private} = $is_private;

   $function_ref->{documentation} = $documentation;
   $function_ref->{description} = $documentation->{summary};

   for (keys %{$function_ref->{documentation}->{args}}){
      if ($_ and $function_ref->{documentation}->{args}->{$_}){
         push @{$function_ref->{args}}, { 
            varname => $_,
            vardescrip => $function_ref->{documentation}->{args}->{$_}
         };
      }    
   }
   if ($function_ref->{documentation}->{vars}->{returns}){
      $function_ref->{returns} = 
         $function_ref->{documentation}->{vars}->{returns}->[0];
   } 
   $function_ref->{vars} = $function_ref->{documentation}->{vars};

}


#
# Map all the class and instance properties to their implementation
#
sub map_all_properties {
   for my $class (keys %CLASSES){
      for my $class_property (@{$CLASSES{$class}->{_class_properties}}){
         my $description = $class_property->{property_doc};
         my $prop_name = $class_property->{property_name};
         my $prop_val = $class_property->{property_value};
         &map_single_property($class, $prop_name, $prop_val, $description, 1);
      }
   }

   for my $class (keys %CLASSES){
      for my $instance_property (@{$CLASSES{$class}->{_instance_properties}}){
         my $description = $instance_property->{property_doc};
         my $prop_name = $instance_property->{property_name};
         my $prop_val = $instance_property->{property_value};
         &map_single_property ($class, $prop_name, $prop_val, $description, 0);
      }
   }

   # Map all the unattached functions
   my $classname = '[default context]';
   &add_class($classname);
   for my $function (grep !($FUNCTIONS{$_}->{is_mapped} || $CLASSES{$_}), 
      keys %FUNCTIONS){
         &map_single_property($classname, $function, $function, '', 1);
   }
}

#
# Map a single instance or class field or method 
#
sub map_single_property {
   my ($class, $prop_name, $prop_val, $description, $is_class_prop) = @_;
   if (!$FUNCTIONS{$prop_val}){
      if (!$is_class_prop){
         push @{$CLASSES{$class}->{instance_fields}}, { 
            field_name => $prop_name,
            field_description => $description
         };
      return;
      } else {
         push @{$CLASSES{$class}->{class_fields}}, { 
            field_name => $prop_name,
            field_description => $description
         };
         return;
      }
   }
   my %method;
   my $function = $FUNCTIONS{$prop_val};
   $function->{is_mapped} = 1;
   $method{mapped_name} = $prop_name;
   $method{argument_list} = $function->{argument_list}; 
   $method{description} = $function->{description};
   $method{args} = $function->{args};
   $method{returns} = $function->{returns};
   $method{vars} = $function->{vars};
   delete $method{vars}->{returns};
   $method{is_private} = $function->{is_private} ? 1 : 0;
   if (!$is_class_prop){
      push @{$CLASSES{$class}->{instance_methods}}, \%method;
   } else {
      push @{$CLASSES{$class}->{class_methods}}, \%method;
   }
}



#
# Build up the full hierarchy of classes, including figuring out
# what methods are overridden by subclasses, etc
# PARAM: The JS source code
#
sub build_class_hierarchy {
   # Find out what is inherited
   for my $class (map($CLASSES{$_}, sort keys %CLASSES)){
      my $superclassname = $class->{extends};
      !$superclassname and next;
      my $superclass = $CLASSES{$superclassname};
      $class->{inherits} = {};
      while ($superclass){
         $class->{inherits}->{$superclassname} = {};
         my @instance_fields;
         my @instance_methods;

         &handle_instance_methods(
            $superclass, 
            $superclassname, 
            $class, 
            \@instance_methods);

         &handle_instance_fields(
            $superclass,
            $superclassname, 
            $class, 
            \@instance_fields );

         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $CLASSES{$superclassname}
         } else {
            $superclass = undef;
         }
      }
   }
}

#
# This is just a helper function for build_class_hierarchy
# because that function was getting way oversized 
#
sub handle_instance_methods {
   my ($superclass, $superclassname, $class, $instance_methods) = @_;
   if ($superclass->{instance_methods}){
      INSTANCE_METHODS: 
      for my $base_method (@{$superclass->{instance_methods}}){
         for $method (@{$class->{instance_methods}}){
            if ($$base_method{mapped_name} eq $$method{mapped_name}){
               next INSTANCE_METHODS;
            }
         }
         for (keys %{$class->{inherits}}){
            my $inherited = $class->{inherits}->{$_};
            for my $method (@{$inherited->{instance_methods}}){
               if ($$base_method{mapped_name} eq $method){
                  next INSTANCE_METHODS;
               }
            }
         }
         push @$instance_methods, $$base_method{mapped_name};
      }
      $class->{inherits}->
      {$superclassname}->{instance_methods} = $instance_methods;
   }
}

#
# This is just a helper function for build_class_hierarchy
# because that function was getting way oversized 
#
sub handle_instance_fields {
   my ($superclass, $superclassname, $class, $instance_fields) = @_;
   if ($superclass->{instance_fields}){
      INSTANCE_FIELDS: 
      for my $base_field  (@{$superclass->{instance_fields}}){
         for my $field (@{$class->{instance_fields}}){
            if ($field eq $base_field){
               next INSTANCE_FIELDS;
            }
         }
         push @$instance_fields, $base_field;
      }
      $class->{inherits}->{$superclassname}->
            {instance_fields} = $instance_fields;
   }
}

#
# Set all the class constructors
#
sub set_class_constructors {
   for my $classname (keys %CLASSES){
      my $constructor = $FUNCTIONS{$classname};
      $CLASSES{$classname}->{constructor_args} = 
         $constructor->{argument_list};
      $CLASSES{$classname}->{constructor_summary} = $constructor->{description};
      $CLASSES{$classname}->{constructor_params} = $constructor->{args};
      $CLASSES{$classname}->{constructor_vars} = $constructor->{vars} || {};
   }
}

#
# Handles a function that has been denoted as a constructor by looking for
# inner functions and properties. Returns the source code minus the
# body of the constructor
#
sub evaluate_constructor {
   my ($doc, $classname, $arglist, $post) = @_;
   my $braces = 0;
   my $func_def = '';   
   while ($braces != -1 and $post =~ /^.*?(\}|\{)/s){
      $post = $';
      $func_def .= "$&" if $braces == 0;
      $braces += ($1 eq '{' ? 1 : -1 );
   }
   
   # Get rid of the documentation
   ($func_def =~ s/(\/\*\*.*?\*\/)//s) && ($doc = $1);
   $func_def =~ s/this/$classname.prototype/g;
   $func_def =~ s/function\s+(\w+)/$classname.prototype.__________$1 = function/g;
   # And then add it back on
   $doc and ($func_def = $doc . $func_def);
   &fetch_funcs_and_classes($func_def);
   return $post;
}

1;
