#!/usr/bin/perl -w

#
# This program makes use of the JSDoc module to make a JavaDoc equivalent
# for JavaScript. The template that is used is based on the JavaDoc
# doclet. This program only needs to be invoked with one or more 
# JS OO sourcefiles as command-line args.
#

use strict;
use HTML::Template;
use File::Copy;
use File::Basename;
use Getopt::Long;
use File::Find;
use Data::Dumper;
use lib dirname($0);
use JSDoc;


use constant LOCATION => dirname($0) . '/';
use constant MAIN_TMPL => LOCATION . "main.tmpl";
use constant ALLCLASSES_TMPL => LOCATION . 'allclasses-frame.tmpl';
use constant ALLCLASSES_NOFRAME_TMPL => LOCATION . 'allclasses-noframe.tmpl';
use constant OVERVIEW_FRAME_TMPL => LOCATION . 'overview-frame.tmpl';
use constant TREE_TMPL => LOCATION . 'overview-tree.tmpl';
use constant OVERVIEW_TMPL => LOCATION . 'overview-summary.tmpl';
use constant INDEX_TMPL => LOCATION . 'index.tmpl';
use constant DEFAULT_DEST_DIR => 'js_docs_out/';
use constant STYLESHEET => 'stylesheet.css';
use constant HELP_TMPL => LOCATION . 'help-doc.tmpl';
use constant INDEX_ALL_TMPL => LOCATION . 'index-all.tmpl';

use vars qw/ $CLASSES $DEFAULT_CLASSNAME @CLASSNAMES @INDEX %TMPL_CACHE
            %CLASS_ATTRS_MAP %METHOD_ATTRS_MAP %OPTIONS @FILENAMES /;

#
# Begin main execution
#

&parse_cmdline;
&initialize_param_maps;

do '.jsdoc_config';
warn "Error parsing config file: $@\n" if $@;

my @sources;
if (@ARGV < 1 || $OPTIONS{HELP} || !(@sources = &load_sources())){
   warn "No sourcefiles supplied\n" if !$OPTIONS{HELP};
   &show_usage();
   exit(1);
}

mkdir($OPTIONS{OUTPUT})
   or die "Can't create output directory $OPTIONS{OUTPUT}: $!\n" 
   unless (-e $OPTIONS{OUTPUT} && -d $OPTIONS{OUTPUT});

# Parse the code tree
&configure_parser(GLOBALS_NAME => $OPTIONS{GLOBALS_NAME});
$CLASSES = &parse_code_tree(@sources);
&output_class_templates();
&output_index_template();
&output_aux_templates();
&output_tree_template();
&_log('Completed generating documentation');

# 
# End main execution
#


#
# Output a single template
#
sub output_template {
   my ($tmplname, $outname, $params, $relaxed) = (@_);
  
   # Caching templates seems to improve performance quite a lot
   if (!$TMPL_CACHE{$tmplname}){
      $TMPL_CACHE{$tmplname} = new HTML::Template( 
         die_on_bad_params    => !$relaxed, 
         filename             => $tmplname);
   }
   my $tmpl = $TMPL_CACHE{$tmplname};
   $tmpl->param($params);
   open FILE, ">$OPTIONS{OUTPUT}$outname"
      or die "Couldn't open '$outname' to write : $!\n";
   print FILE $tmpl->output;
   close FILE;
}

#
# Gather information for each class and output its template
#
sub output_class_templates {
  
   # Note the class name for later
   @CLASSNAMES = sort { $a->{classname} cmp $b->{classname}} 
      map {classname => $_}, keys %$CLASSES;

   my %fnames = map { 
      ($$CLASSES{$_}->{constructor_vars}->{filename} or '') => 1  
   } keys %$CLASSES; 
   
   @FILENAMES = map {filename => $_}, 
      sort {uc($a) cmp uc($b)} grep {length $_} keys %fnames;

   for (my $i = 0; $i < @CLASSNAMES; $i++){
      my $classname = $CLASSNAMES[$i]->{classname};

      # Template Parameters
      my ($class, $subclasses, $class_summary, @constructor_params, 
         $next_class, $prev_class, $constructor_attrs);

      $class= $$CLASSES{$classname};

      &add_to_index($class, $classname);

      # Set up the constructor and class information
      &resolve_synonyms($class->{constructor_vars});
      &format_vars($class->{constructor_vars});
      @constructor_params = 
         &fetch_args($class->{constructor_vars}, \$class->{constructor_args});
      $constructor_attrs = 
         &format_method_attributes($class->{constructor_vars});
      $class_summary = &resolve_inner_links($class->{constructor_summary});
      $class_summary =~ s/TODO:/<br><b>TODO:<\/b>/g if $class_summary;
      $class_summary .= &format_class_attributes($class->{constructor_vars});

      # Navbar information
      $next_class = $i + 1 < @CLASSNAMES ? $CLASSNAMES[$i + 1]->{classname} 
         : undef; 
      $prev_class = $i > 0 ? $CLASSNAMES[$i - 1]->{classname} : undef;

      # Find all the direct subclasses
      $subclasses = join( ',',
         map qq| <a href="$_.html">$_</a>|, @{&find_subclasses($classname)});
      
      &output_template(MAIN_TMPL, "$classname.html", 
         {
            next_class           => $next_class,
            prev_class           => $prev_class,
            superclass           => $class->{extends},
            constructor_args     => $class->{constructor_args},
            constructor_params   => \@constructor_params,
            constructor_attrs    => $constructor_attrs,
            constructor_returns  => 
               ref($class->{constructor_vars}->{returns}[0]) eq 'ARRAY' ? 
                  $class->{constructor_vars}->{returns}[0][0] : 
                  $class->{constructor_vars}->{returns}[0],
            class_summary        => $class_summary,
            classname            => $classname,
            subclasses           => $subclasses,
            class_tree           => &build_class_tree($classname, $CLASSES),
            fields               => &map_fields($class),
            methods              => &map_methods($class), 
            method_inheritance   => &map_method_inheritance($class),
            field_inheritance    => &map_field_inheritance($class),
            inner_classes        => $class->{inner_classes},
            project_name         => $OPTIONS{PROJECT_NAME},
            page_footer          => $OPTIONS{PAGE_FOOTER},
      }, 1);
   }
}


#
# Output all the non-class template files
#
sub output_aux_templates(){
   
   unless ($OPTIONS{LOGO} and -f $OPTIONS{LOGO} and -r $OPTIONS{LOGO}){
      $OPTIONS{LOGO} and warn "Can't read $OPTIONS{LOGO}";
      $OPTIONS{LOGO} = '';
   }
   $OPTIONS{LOGO} and copy $OPTIONS{LOGO}, $OPTIONS{OUTPUT};

   my $summary = '';
   if ($OPTIONS{PROJECT_SUMMARY}){
      if (-f $OPTIONS{PROJECT_SUMMARY} and 
            open SUMMARY, $OPTIONS{PROJECT_SUMMARY}){
         local $/ = undef;
         $summary = <SUMMARY>;
         close SUMMARY;
      } else {
         warn "Can't open $OPTIONS{PROJECT_SUMMARY}";
      }
   }

   $DEFAULT_CLASSNAME = $CLASSNAMES[0]->{classname};
   
   my $params = {    
      filename    => 'All Classes',
      CLASSNAMES  => \@CLASSNAMES };
   if (@FILENAMES < 2){
      $params->{project_name} = $OPTIONS{PROJECT_NAME};
      $params->{logo} = basename($OPTIONS{LOGO});
   }
   &output_template(ALLCLASSES_TMPL, 'allclasses-frame.html', $params);

   &output_template(ALLCLASSES_NOFRAME_TMPL, 'allclasses-noframe.html',
      {  CLASSNAMES     => \@CLASSNAMES,
         project_name   => $OPTIONS{PROJECT_NAME},
         logo           => basename($OPTIONS{LOGO}) 
      });

   if (@FILENAMES > 1){

      &output_template(OVERVIEW_FRAME_TMPL, 'overview-frame.html',
         {  logo           => basename($OPTIONS{LOGO}),
            project_name   => $OPTIONS{PROJECT_NAME},
            filenames      => \@FILENAMES
         });

      for my $fname (map { $_->{filename}} @FILENAMES){
         my @classes = 
            grep {
               ($$CLASSES{$_}->{constructor_vars}->{filename} || '')  eq $fname
            } keys %$CLASSES;
     
         &output_template(ALLCLASSES_TMPL, "overview-$fname.html",
            {  filename    => $fname, 
               CLASSNAMES  => [map {classname => $_}, sort @classes]
            }); 

      }
   }
   
   # Output the main index template
   &output_template(INDEX_TMPL, 'index.html', 
      {  DEFAULT_CLASSNAME => 
            ($summary ? 'overview-summary' : $DEFAULT_CLASSNAME),
         multifile => @FILENAMES > 1
      });

   # Output the help document template
   &output_template(HELP_TMPL, 'help-doc.html',  
      { page_footer => $OPTIONS{PAGE_FOOTER}, 
         project_name => $OPTIONS{PROJECT_NAME} });
   
   copy (LOCATION . STYLESHEET, $OPTIONS{OUTPUT} . STYLESHEET);

   &output_template(OVERVIEW_TMPL, 'overview-summary.html',
      {  project_name      => $OPTIONS{PROJECT_NAME},
         page_footer       => $OPTIONS{PAGE_FOOTER},
         project_summary   => $summary });
}


# 
# Build the tree representation of the inheritance
# PARAM: Name of the class
#
sub build_class_tree {
   my $classname  = shift;
   my $class = $$CLASSES{$classname};
   my $tree = "";
   my @family;
   push @family, $classname;
   while ($class->{extends} and $class->{extends} ne ""){
      push @family, "<a href=\"" . $class->{extends} . ".html\">" . 
	 $class->{extends} . "</a>";
      $class = $$CLASSES{$class->{extends}};
   }
   push @family, "Object";
   my $indent = 3;
   $tree = (pop @family) . "\n";
   my $name = $_;
   while ($name = pop (@family)){
      $tree .= " " x $indent; 
      $tree .= "|\n";

      $tree .= " " x $indent;
      $tree .= "+--";
      $name eq $classname and $tree .= "<b>";
      $tree .= $name;
      $name eq $classname and $tree .= "</b>";
      $tree .= "\n";
      $indent += 6;
   }
   $tree;
}

#
# Shown if no commandline args are given
#
sub show_usage(){
   print qq{Usage: jsdoc [OPTIONS] <js sourcefiles and/or directories>+
   
   -h | --help          Show this message and exit
   -r | --recursive     Recurse through given directories
   -p | --private       Show private methods and fields
   -d | --directory     Specify output directory (defaults to js_docs_out)
   -q | --quiet         Suppress normal output 


   --page-footer        Specify (html) footer string that will be added to 
                        all docs
   --project-name       Specify project name for that will be added to docs 
   --logo               Specify a path to a logo to be used in the docs 
   --project-summary    Specify a path to a text file that contains an 
                        overview summary of the project 
                        
   --globals-name       Specify a 'class name' under which all unattached
                        methods will be classified. The defaults to GLOBALS
                        \n};

}

# 
# Take all the command line args as filenames and add them to @SOURCESFILES 
#
sub load_sources(){
   my (@filenames, @sources);
   for my $arg (@ARGV){
      if (-d $arg){
         $arg =~ s/(.*[^\/])$/$1\//; 
         find( { 
            wanted => sub { 
                  push @filenames, $_ if 
                     (-f and -r and /.+\.js$/i) && 
                     (/$arg[^\/]+$/ || $OPTIONS{RECURSIVE}) 
               }, 
            no_chdir => 1 }, $arg);
      } elsif (-f $arg){
         push @filenames, $arg;
      }   
   }
   for (@filenames){
      &_log("Loading sources from $_");
      open SRC, "<$_" or  (warn "Can't open $_, skipping: $!\n" and next);
      local $/ = undef;
      push @sources, (fileparse($_))[0];
      push @sources, \<SRC>;
      close SRC;
   }
   @sources;
}

#
# Once all sources have been parsed, finds all subclasses
# of $classname
#
sub find_subclasses(){
   my ($classname) = @_;
   my @subclasses;
   for my $class (keys %$CLASSES){
      my $subclassname = $$CLASSES{$class}->{extends};
      if ($$CLASSES{$class}->{extends} and 
	 $$CLASSES{$class}->{extends} eq $classname){
	    push @subclasses,  $class;
      }
   }
   \@subclasses;
}

#
# Make a summary of a description, cutting it off either at the first
# double newline or the first period followed by whitespace.
# PARAM: $description
#
sub get_summary {
   my ($description) = @_;
   my $summary;
   if ($description){
      ($summary) = $description =~ /^(.*?(?:[?!.](?=\s)|\n\n)).*$/gs
	 or $summary = $description;
   } else {
      $summary = "";
   }
   $summary;
}


#
# Set up all the instance and class methods for one template
# PARAM: A reference to a class
#
sub map_methods{
   my $class = shift;
   my @methods;
   for my $method ( 
      sort {$a->{mapped_name} cmp $b->{mapped_name} }  
      @{$class->{instance_methods}}){
         &resolve_synonyms($method->{vars}); 
         next if (!$OPTIONS{PRIVATE} && $method->{vars}->{private});
         $method->{vars}->{returns}[0] = 
            $method->{vars}->{returns}[0] || $method->{vars}->{return};
         my @args = &fetch_args($method->{vars}, \$method->{argument_list});
         @args = map { &format_vars($_); $_ } @args; 
         &format_vars($method->{vars});
         push @methods, {
            method_description => &resolve_inner_links($method->{description}),
            method_summary => &resolve_inner_links(
               &get_summary($method->{description})),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => ref($method->{vars}->{returns}[0]) eq 'ARRAY' ? $method->{vars}->{returns}[0][0] : $method->{vars}->{returns}[0],
            is_class_method => 0,
            is_private => defined($method->{vars}->{private}), 
            attributes => &format_method_attributes($method->{vars}),
            type => &map_return_type($method)
            };
   }
   for my $method ( sort {$a->{mapped_name} cmp $b->{mapped_name} } 
      @{$class->{class_methods}}){
         &resolve_synonyms($method->{vars}); 
         next if (!$OPTIONS{PRIVATE} && $method->{vars}->{private});
         my @args = &fetch_args($method->{vars}, \$method->{argument_list});
         @args = map { &format_vars($_); $_ } @args; 
         &format_vars($method->{vars});
         push @methods, {
            method_description => &resolve_inner_links($method->{description}),
            method_summary => &resolve_inner_links(
               &get_summary($method->{description})),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => $method->{vars}->{returns}[0],
            is_class_method => 1,
            is_private => defined($method->{vars}->{private}), 
            attributes => &format_method_attributes($method->{vars}),
            type => &map_return_type($method)
            }; 
   }
   \@methods;
}

#
# Map a function return type
#
sub map_return_type {
   my ($method) = @_;
   if ($method->{vars}->{type}[0]){
      my ($name) = $method->{vars}->{type}[0] =~ /(\w+(?:\.\w+)*)/;
      if ($$CLASSES{$name}){
         return qq|<a href="$name.html">$name</a>|;
      }
      return $name;
   }
   return 'function';
}

#
# Set up all the instance and class methods for one template
# PARAM: A reference to a class
#
sub map_fields {
   my $class = shift;
   my @fields;
   # Set up the instance fields
   for (sort {$a->{field_name} cmp $b->{field_name} } 
      @{$class->{instance_fields}}){
         &resolve_synonyms($_->{field_vars});
         next if (!$OPTIONS{PRIVATE} && $_->{field_vars}->{private});
         push @fields, { 
         field_name => $_->{field_name}, 
         field_description => &resolve_inner_links($_->{field_description}), 
         field_summary => &resolve_inner_links(
            &get_summary($_->{field_description})),
         is_final => defined($_->{field_vars}->{final}),
         is_private => defined($_->{field_vars}->{private}),
         is_class_field => 0,
         type => &map_field_type($_)
         };
   }


   # Set up the class fields 
   if ($class->{class_fields}){
      for (sort {$a->{field_name} cmp $b->{field_name} } 
         @{$class->{class_fields}}){
            &resolve_synonyms($_->{field_vars});
            next if (!$OPTIONS{PRIVATE} && $_->{field_vars}->{private});
            push @fields, { 
               field_name => $_->{field_name}, 
               field_description => &resolve_inner_links( 
                  $_->{field_description}), 
               field_summary => &resolve_inner_links(
                  &get_summary($_->{field_description})),
               is_final => defined($_->{field_vars}->{final}),
               is_private => defined($_->{field_vars}->{private}),
               is_class_field => 1,
               type => &map_field_type($_)
               };
      }
   }
   \@fields;
}

#
# Map a field type
#
sub map_field_type {
   my ($field) = @_;
   if ($field->{field_vars}->{type}[0]){
      my ($name) = $field->{field_vars}->{type}[0] =~ /(\w+(?:\.\w+)*)/;
      if ($$CLASSES{$name}){
         return qq|<a href="$name.html">$name</a>|;
      }
      return $name;
   }
   return 'var';
}


#
# Map all the inherited methods to a template parameter
# PARAM: A reference to a class
#
sub map_method_inheritance {
   my $class = shift;
   my @method_inheritance; 
   # Set up the inherited methods
   if ($class->{inherits}){
      my $superclassname = $class->{extends};
      my $superclass = $$CLASSES{$superclassname};
      while ($superclass){
         my $methods = 
            $class->{inherits}->{$superclassname}->{instance_methods};
         if ($methods and @$methods){
            push @method_inheritance, {
               superclass_name => $superclassname,
               inherited_methods => join(', ', 
                     map(qq|<a href="$superclassname.html#$_">$_</a>|, &filter_private_methods($methods, $superclassname)))};
         }
         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $$CLASSES{$superclassname};
         } else {
            $superclass = undef;
         }
      }
   }
   \@method_inheritance;
}

#
# Map all the inherited fields to a template parameter
# PARAM: A reference to a class
#
sub map_field_inheritance {
   my $class = shift;
   my @field_inheritance;
   # Set up the inherited fields 
   if ($class->{inherits}){
      my $superclassname = $class->{extends};
      my $superclass = $$CLASSES{$superclassname};
      while ($superclass){
         my $fields = $class->{inherits}->{$superclassname}->{instance_fields};
         if ($fields and @$fields){
            push @field_inheritance, 
               {
                  superclass_name => $superclassname,
                  inherited_fields => join(', ', 
                     map(qq|<a href="$superclassname.html#$_">$_</a>|, &filter_private_fields($fields, $superclassname)))};
         }
         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $$CLASSES{$superclassname};
         } else {
            $superclass = undef;
         }
      }
   }
   \@field_inheritance;
}

#
# Filter out private inherited methods
#
sub filter_private_methods {
   my ($methods, $superclassname) = @_;
   my @visible_methods;
   for my $method(@$methods){
      for my $super_method (@{$$CLASSES{$superclassname}->{instance_methods}}){
         push @visible_methods, $method 
            if $method eq $super_method->{mapped_name} and 
               (!$super_method->{vars}->{private} || $OPTIONS{PRIVATE});
      }
   }
   @visible_methods;
}

#
# Filter out private inherited fields
#
sub filter_private_fields {
   my ($fields, $superclassname) = @_;
   my @visible_fields;
   for my $field (map {$_->{field_name}} @$fields){
      for my $super_field(@{$$CLASSES{$superclassname}->{instance_fields}}){
         push @visible_fields, $field
            if $field eq $super_field->{field_name} and
               (!$super_field->{field_vars}->{private} || $OPTIONS{PRIVATE});
      }
   }
   @visible_fields;
}

#
# Adds a class's information to the global INDEX list 
#
sub add_to_index {
   my ($class, $classname) = @_;
   push @INDEX, { 
      name => $classname, 
      class => $classname, 
      type => '', linkname => '' 
   };

   if (!$class->{constructor_args}){
      $class->{constructor_args} = '';
   } else {
      push @INDEX, 
         {
            name => "$classname$class->{constructor_args}",
            class => $classname,
            type => 'Constructor in ',
            linkname => 'constructor_detail'
         };
   }
   for my $method(@{$class->{class_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}", 
            class => $classname,
            type => 'Class method in ',
            linkname => $method->{mapped_name}
         } unless ($method->{vars}->{private} and not $OPTIONS{PRIVATE});
   }
   for my $method (@{$class->{instance_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}",
            class => $classname,
            type => 'Instance method in ',
            linkname => $method->{mapped_name}
         } unless ($method->{vars}->{private} and not $OPTIONS{PRIVATE});

   }
   for my $class_field (@{$class->{class_fields}}){
      push @INDEX, 
         {
            name => $class_field->{field_name},
            class => $classname,
            type => 'Class field in ',
            linkname => $class_field->{field_name}
         };
   }
   for my $instance_field (@{$class->{instance_fields}}){
      push @INDEX,
         {
            name => $instance_field->{field_name},
            class => $classname,
            type => 'Instance field in ',
            linkname => $instance_field->{field_name}
         };
   }
}

#
# Outputs the index page
#
sub output_index_template { 
   @INDEX = sort {$a->{name} cmp $b->{name}} @INDEX;
   my %letters;
   for my $item (@INDEX){
      my $letter = uc(substr($item->{name}, 0, 1));
      if ($letter eq ''){
         $letter = uc(substr($item->{class}, 0, 1));
      }
      push @{$letters{$letter}}, $item; 
   }
   
   my $letter_list = [map {letter_name => $_}, sort {$a cmp $b} keys %letters];
   &output_template(INDEX_ALL_TMPL, 'index-all.html', 
      {  letters        => $letter_list,
         project_name   => $OPTIONS{PROJECT_NAME},
         page_footer    => $OPTIONS{PAGE_FOOTER},
         index_list     => [map {
                              letter => $_->{letter_name}, 
                              value => $letters{$_->{letter_name}}
                           }, @{$letter_list}]
      });
}

#
# Recursively builds up the overview tree
#
sub build_tree 
{
   my $parentclassname = shift || '';
   my $ret = "";
   for my $cname (map {$_->{classname}} @CLASSNAMES) 
   {
      next if $cname eq $OPTIONS{GLOBALS_NAME};
      my $class = $$CLASSES{$cname};
      my $parent = $class->{extends} || '-';
      if (!($parentclassname || $class->{extends}) 
            or ($parent eq $parentclassname))
      {
         $ret .= qq{
            <LI TYPE="circle">
               <A HREF="$cname.html">
            <B>$cname</B></A></LI>
         };
         my $childrentree .= &build_tree($cname);		
         $ret = "$ret<UL>$childrentree</UL>" unless not $childrentree;
      }
   }
   $ret = "<UL>$ret</UL>" unless not $ret;
   $ret;
}

#
# Outputs the overview tree
#
sub output_tree_template {
   my $tree = &build_tree();
   &output_template(TREE_TMPL, 'overview-tree.html',
      {  classtrees     => $tree,
         project_name   => $OPTIONS{PROJECT_NAME},
         page_footer    => $OPTIONS{PAGE_FOOTER}
      }, 1);
}

#
# Formats additional non-standard attributes for methods according to user 
# configuration
#
sub format_method_attributes {
   my ($attrs) = shift;
   my $attributes = '';
   while (my ($name, $val) = each %{$attrs}) {
      $attributes .= &{$METHOD_ATTRS_MAP{$name}}($val) 
         if $METHOD_ATTRS_MAP{$name};
   }
   $attributes;
}

#
# Formats additional non-standard attributes for classes according to user 
# configuration
#
sub format_class_attributes {
   my ($attrs) = shift;
   my $attributes = '<BR/><BR/>';
   while (my ($name, $val) = each %{$attrs}) {
      $attributes .= &{$CLASS_ATTRS_MAP{$name}}($val) 
         if $CLASS_ATTRS_MAP{$name};
   }
   $attributes;
}


#
# Parses the command line options
#
sub parse_cmdline {
   $OPTIONS{OUTPUT} = DEFAULT_DEST_DIR;
   $OPTIONS{PROJECT_NAME} = '';
   $OPTIONS{COPYRIGHT} = '';
   $OPTIONS{PROJECT_SUMMARY} = '';
   $OPTIONS{LOGO} = '';
   $OPTIONS{GLOBALS_NAME} = 'GLOBALS';
   GetOptions(
      'private|p'          => \$OPTIONS{PRIVATE},
      'directory|d=s'      => \$OPTIONS{OUTPUT},
      'help|h'             => \$OPTIONS{HELP},
      'recursive|r'        => \$OPTIONS{RECURSIVE},
      'page-footer=s'      => \$OPTIONS{PAGE_FOOTER},
      'project-name=s'     => \$OPTIONS{PROJECT_NAME},
      'project-summary=s'  => \$OPTIONS{PROJECT_SUMMARY},
      'logo=s'             => \$OPTIONS{LOGO},
      'globals-name=s'     => \$OPTIONS{GLOBALS_NAME},
      'quiet|q'            => \$OPTIONS{QUIET}
   );
   $OPTIONS{OUTPUT} =~ s/([^\/])$/$1\//;
}

#
# Resolves links for {@link } items
#
sub resolve_inner_links {
   my $doc = shift;
   $doc =~ s{\{\@link\s+([^\}]+)\}}{&format_link($1)}eg if $doc;
   return $doc;
}

#
# Formats a {@link } item
#
sub format_link {
   my ($link) = shift;
   $link =~ s/\s*(.*?)\s*/$1/;
   $link =~ s/<[^>]*>//g; 
   my ($class, $method, $label) = 
      $link =~ /^([^\s#]+)?(?:#(\w+(?:\.\w+)*))?\s*(.*)$/
         or return $link;
   if ($class){
      unless ($$CLASSES{$class}){
         warn "\@link can't find reference $class\n";
         return $link;
      }
   }
   if (!$method){
      $label = $class unless $label;
      "<a href=\"$class.html#\">$label<\/a>";
   } else {
      if ($class){
         my $ismethod = grep { 
               $_->{mapped_name} eq $method 
            } (@{$CLASSES->{$class}->{instance_methods}},
                  @{$CLASSES->{$class}->{class_methods}});
         my $isfield = grep {
               $_->{field_name} eq $method
            } (@{$CLASSES->{$class}->{instance_fields}},
                  @{$CLASSES->{$class}->{class_fields}}) unless $ismethod;
         $label = "$class.$method" . ($ismethod ? '()' : '') unless $label;
         if ($ismethod or $isfield){
            "<a href=\"$class.html#$method\">$label</a>";
         } else {
            warn "\@link can't find reference $method in $class\n";
            $link;
         }
      } else {
         $label = "$method()" unless $label;
         "<a href=\"#$method\">$label</a>";
      }
   }
}


#
# Initializes the customizable maps for @attributes
#
sub initialize_param_maps {
   %CLASS_ATTRS_MAP  = (
      author =>
         sub {
            '<B>Author:</B> ' .
               join(', ', @{$_[0]}) . "<BR/>" 
         },
      deprecated =>
         sub {
            '<B>Deprecated</B> <I>' . ($_[0] ? $_[0]->[0] : '') . 
            "</I><BR/><BR/>";
         },
      see =>
         sub {
            '<B>See:</B><UL>- ' .
            join('<BR/>- ', map {&format_link($_)} @{$_[0]}) . "</UL>"
         },
      version =>
         sub {
            '<B>Version: </B>' .
               join(', ', @{$_[0]}) . '<BR/><BR/>' 
         },
      requires =>
         sub {
            '<B>Requires:</B><UL>- ' .
            join('<BR/>- ', map {&format_link($_)} @{$_[0]}) . "</UL>"
         },
      filename =>
         sub {
            "<I>Defined in $_[0]</I><BR/><BR/>";
         }
   );
   
   %METHOD_ATTRS_MAP = (
      throws => 
         sub { 
         "<B>Throws:</B><UL>- " .  
         join("<BR>- ", @{$_[0]}) . "</UL>"
      },
   );
   $METHOD_ATTRS_MAP{exception} = $METHOD_ATTRS_MAP{throws};
   $METHOD_ATTRS_MAP{author} = $CLASS_ATTRS_MAP{author};
   $METHOD_ATTRS_MAP{deprecated} = $CLASS_ATTRS_MAP{deprecated};
   $METHOD_ATTRS_MAP{see} = $CLASS_ATTRS_MAP{see};
   $METHOD_ATTRS_MAP{requires} = $CLASS_ATTRS_MAP{requires};
}


# 
# Parse the @param or @argument values into name/value pairs and 
# return the list of them
#
sub fetch_args {
   my ($vars, $arg_list_ref) = @_;
   return unless $vars and $$arg_list_ref;
   my (@args, %used);
   for my $arg (split /\W+/, ($$arg_list_ref =~ /\(([^)]*)/)[0]){
      for (@{$vars->{param}}){
         my ($type, $name, $value) = /(?:\{(\w+(?:\.\w+)*)\})?\s*(\w+)(.*)/;
         next unless $name eq $arg;
         $used{$name} = 1;
         #push @args, { varname => $name, vardescrip => $value};
         $type ||= '';
         $type =  qq|<a href="$type.html">$type</a>| if $$CLASSES{$type};
         my $type_regex = qr{\b$arg\b};
         $$arg_list_ref =~ s/($type_regex)/&lt;$type&gt; $1/ if $type;
         push @args, { varname => $name, vardescrip => $value};
      }
   }
   for (@{$vars->{param}}){
      my ($type, $name, $value) = /(?:\{(\w+(?:\.\w+)*)\})?\s*(\w+)(.*)/;
      next if $used{$name};
      push @args, { varname => $name, vardescrip => $value };
   }
   @args;
}

sub resolve_synonyms {
   my ($item) = @_;
   $item->{param} = $item->{param} || $item->{argument};
   $item->{returns} = $item->{return} || $item->{returns};
   $item->{final} = $item->{final} || $item->{const};
}

#
# Log a message to STDOUT if the --quiet switch is not used
#
sub _log {
   print $_[0], "\n" unless $OPTIONS{QUIET};
}

#
# Takes a vars hash and resolves {@link}s within it
#
sub format_vars {
   my ($vars) = @_;
   for my $key (keys %$vars){
      if (ref($vars->{$key}) eq 'ARRAY'){
         for (0..$#{$vars->{$key}}){
            $vars->{$key}->[$_] = &resolve_inner_links($vars->{$key}->[$_]);
         }
      } else {
         $vars->{$key} = &resolve_inner_links($vars->{$key});   
      }
   }
}
