package JSDoc;

=head1 NAME

JSDoc - parse JavaScript source file for JSDoc comments

=head1 SYNOPSIS

Create JavaScript sourcefiles commented in a manner similar to javadoc
(ie. with documentation starting with '/**' and then pass a list of references 
to JavaScript source to parse_code_tree:

   /**
    * This is a class for example purposes
    * @param name Name for the new object
    * @constructor
    */
    function MyClass(name){
      this.name = name;
    }

   $code_tree = parse_code_tree(@src_refs);

A tree structure describing the code layout, inheritance and documentation
is returned

To clear the cache of classes and functions in the parser:

   reset_parser();
    

=head1 DESCRIPTION

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
      +- constructor_vars
      |
      +- class_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- vars 
      |
      +- instance_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- vars 
      | 
      +- class_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name
      |  |
      |  +- field_vars
      |
      +- instance_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name
      |  |
      |  +- field_vars
      |
      +- inherits
         |
         +- Class
            |
            +- instance_fields
            |
            +- instance_methods

=head1 AUTHOR

mmathews@jscan.org,
Gabriel Reid gab_reid@users.sourceforge.net

=cut

require 5.000;
use Carp;
use Exporter;
use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(parse_code_tree reset_parser);

use vars qw/ %CLASSES %FUNCTIONS /;
#
# Public function that returns a datastructure representing the JS classes
# and their documentation
#
sub parse_code_tree {
   for my $js_src (map { ${$_} } @_){
      
      # perlify os line-endings
      $js_src =~ s/(\r\n|\r)/\n/g;

      # remove all uninteresting comments, but only if they're not inside
      # of other comments
      {
         no warnings;
         $js_src =~ s{(/\*[^*]*\*+(?:[^/*][^*]*\*+)*/)|//.*}{$1}g;
      }

      &fetch_funcs_and_classes($js_src);
   }
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
# Parses up a a jsdoc comment into its component parts
# PARAM: The document string to be parsed
#
sub parse_jsdoc_comment {
   my $doc = shift;

   $doc =~ s/^\s*\*//gm;

   # remember each part that is parsed
   my %parsed = ();

   # the first paragraph could be a summary statement
   # a paragraph may follow of variable defs (variable names start with "@")
   my ($summary, $variable_str) = $doc =~ 
                     /^\s*
                     (
                        (?:[^{@]|(?:\{[^@]))*
                        (?:\{\@
                           (?:[^{@]|(?:\{[^@]))*
                        )*)
                     \s*
                     (.*)
                     $/xs;

   $parsed{summary} = $summary;


   # two types of variable def can be dealt with here:
   # a @argument has a two-part value -- the arg name and a description
   # all other @<variables> only have a single value each (although there may
   # be many variables with the same name)
   if($variable_str) {
       my %vars = ();
       while ($variable_str =~ /(?!\{)\@(\w+)(?!\})\s*([^\@]*)\s*/gs) {
           my ($name, $val) = ($1, $2);
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
         # Documentation
         (?:
            /\*\*                         # Opening of docs
               ([^/]+
                  (?:(?:[^*]/)+[^/]+)*
               )
            \*/\s*\n\s*                   # Closing of docs
         )?
         
         # Function
         (?:(?:function\s*(\w+)\s*(\(.*?\))\s*\{)|         
         
         # Anonymous function
         (?:(\w+)(\.prototype)?\.(\w+)\s*=\s*function\s*(\(.*?\)))|  

         # Instance property 
         (?:(\w+)\.prototype\.(\w+)\s*=\s*(.*?);)|    

         #Inheritance
         (?:(\w+)\.prototype\s*=\s*new\s*(\w+)\(.*?\)\s*;)| 

         # Class property
         (?:(\w+)\.(\w+)\s*=\s*(.*?);))        
      !gsx){

      my $doc;
      $doc = $1 or $doc = "";


      if ($2){
         my ($func, $arglist, $post) = ($2, $3, $');
         &add_function($doc, $func, $arglist);
         if ($doc =~ /\@constructor/){
            # 
            # Because this is marked as a constructor, we always add it
            # as a class
            #
            &add_class($func);
            $js_src = &evaluate_constructor($doc, $func, $arglist, $post);
         }
      } elsif ($4 && $6 && $FUNCTIONS{$4}){
         # Anonymous functions added onto a class or class prototype
         &add_anonymous_function($doc, $4, $6, $7, not defined($5));
      } elsif ($4 && $6 && not defined($FUNCTIONS{$4})){
         # Called for methods added to the prototype of core classes
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
   
   # This is dirty
   my $is_private = $function_name =~ s/^__________// || $doc =~ /\@private/;

   &add_function($doc, $fake_name, $arg_list, $is_private) and
      &add_property(
         $doc, $class, $function_name, $fake_name, $is_class_prop);

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
   my $parsed_doc = &parse_jsdoc_comment($doc);
   $doc = $parsed_doc->{summary};
   my $key = $is_class_property ? '_class_properties' : '_instance_properties';
   for my $classref (@{$CLASSES{$class}->{$key}}){
      if ($classref->{property_name} eq $property){
         warn "Already bound property '$property' to '$class'\n";
         return;
      }
   }

   push @{$CLASSES{$class}->{$key}}, 
      {
	 property_doc => $doc,
	 property_name => $property,
	 property_value => $value,
         property_vars => $parsed_doc->{vars} 
      };
}


#
# Add a function and its documentation to the global FUNCTION hash
#
sub add_function {
   my ($doc, $function, $arg_list, $is_private) = @_;
   if ($FUNCTIONS{$function}){
      warn "Function $function already declared\n";
      return 0;
   }
   $FUNCTIONS{$function} = {};
   my $func = $FUNCTIONS{$function};
   $arg_list and $func->{argument_list} = join(" ", split("\\s+", $arg_list))
      or $func->{argument_list} = "()";
    
   my $documentation = parse_jsdoc_comment($doc);
   my $function_ref = $FUNCTIONS{$function};
   
   $function_ref->{documentation} = $documentation;
   $function_ref->{description} = $documentation->{summary};

   $function_ref->{vars} = $function_ref->{documentation}->{vars};
   $function_ref->{vars}->{private} = 1 if $is_private;
   1;
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
         my $prop_vars = $class_property->{property_vars};
         &map_single_property(
            $class, $prop_name, $prop_val, $description, $prop_vars, 1);
      }
   }

   for my $class (keys %CLASSES){
      for my $instance_property (@{$CLASSES{$class}->{_instance_properties}}){
         my $description = $instance_property->{property_doc};
         my $prop_name = $instance_property->{property_name};
         my $prop_val = $instance_property->{property_value};
         my $prop_vars = $instance_property->{property_vars};
         &map_single_property (
            $class, $prop_name, $prop_val, $description, $prop_vars, 0);
      }
   }

   # Map all the unattached functions
   my $classname = '[default context]';
   &add_class($classname);
   for my $function (grep !($FUNCTIONS{$_}->{is_mapped} || $CLASSES{$_}), 
      keys %FUNCTIONS){
         &map_single_property($classname, $function, $function, '', undef, 1);
   }
}

#
# Map a single instance or class field or method 
#
sub map_single_property {
   my ($class, $prop_name, $prop_val, 
      $description, $vars, $is_class_prop) = @_;

   if (!$FUNCTIONS{$prop_val}){
      if (!$is_class_prop){
         push @{$CLASSES{$class}->{instance_fields}}, { 
            field_name => $prop_name,
            field_description => $description,
            field_vars => $vars
         };
         return;
      } else {
         push @{$CLASSES{$class}->{class_fields}}, { 
            field_name => $prop_name,
            field_description => $description,
            field_vars => $vars
         };
         return;
      }
   }
   my %method;
   my $function = $FUNCTIONS{$prop_val};
   $function->{is_mapped} = 1;
   $method{mapped_name} = $prop_name;

   $method{$_} = $function->{$_} for 
      qw/ argument_list description vars /;

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
  
   # Build a table of internally defined public methods
   my %method_map;
   while (($func_def =~ /this.(\w+)\s*=\s*([_a-zA-Z]+\w*)\s*;/g)){
      $method_map{$2} = $1;
   }
   $func_def =~ s/this(?=\.\w+\s*=\s*function)/$classname.prototype/g;
   
   my %inner_funcs = map { $_ => 1 } $func_def =~ /function\s+(\w+)/g;
 
   $func_def =~ 
      s/
         this(?=\.\w+\s*=\s*
         (('[^'\n]*')|("[^"\n]*")|\w+))/$classname.prototype/gx;

   $func_def =~ s/
      function\s+(\w+)
      (?=\([^)]*\))/
      {
         "$classname.prototype." . 
         ($method_map{$1} ? $method_map{$1} : "__________$1") . 
         " = function"
      }/egx;
   
   # Sweep out all the converted assignments of inner functions
   $func_def =~ s/
   ($classname\.prototype\.\w+\s*=\s*(\w+))/
   {
      $inner_funcs{$2} ? '' : "$1"
   }/egx;
   &fetch_funcs_and_classes($func_def);
   return $post;
}

# 
# Clear out everything from the parsed classes and functions
#
sub reset_parser 
{
	%CLASSES = ();
	%FUNCTIONS = ();
}

1;
