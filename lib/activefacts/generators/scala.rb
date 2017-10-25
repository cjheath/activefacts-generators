#
#       ActiveFacts Generators.
#       Generate a Scala module for the ActiveFacts API from an ActiveFacts vocabulary.
#
# Copyright (c) 2013 Clifford Heath. Read the LICENSE file.
#
require 'activefacts'
require 'activefacts/metamodel'
require 'activefacts/generators/helpers/oo'
require 'activefacts/generators/traits/scala'
require 'activefacts/registry'

module ActiveFacts
  module Generators
    # Generate Scala module containing classes for an ActiveFacts vocabulary.
    # Invoke as
    #   afgen --scala[=options] <file>.cql
    # Options are comma or space separated:
    # * help list available options

    class Scala < Helpers::OO

      def initialize(vocabulary, *options)
        super
        @constraints_used = {}
        @fact_types_dumped = {}
      end

    private

      def set_option(option)
        @mapping = false
        case option
        when 'help', '?'
          $stderr.puts "Usage:\t\tafgen --scala[=option,option] input_file.cql\n"+
              "\t\tmeta\t\tModify the mapping to suit a metamodel"
          exit 0
        when /^meta/
          @is_metamodel = true
        else super
        end
      end

      def fact_type_name(fact_type)
        fact_type.default_reading.words
      end

      def vocabulary_start
        puts @vocabulary.scala_prelude

        @metamodel = @vocabulary.scala_prelude_metamodel
      end

      def vocabulary_end
        puts @vocabulary.scala_finale
        puts "#{@metamodel}\n}\n"
      end

      def data_type_dump(o)
      end

      def value_type_dump(o, super_type_name, facets)
        puts o.scala_definition(super_type_name, facets)

        @metamodel << o.scala_metamodel(super_type_name, facets)
      end

      def id_role_names o, id_roles
        id_roles.map do |role|
          # Ignore identification through a supertype
          next if role.fact_type.kind_of?(ActiveFacts::Metamodel::TypeInheritance)
          role.preferred_role_name(o).words.camelcase
        end.compact
      end

      def id_role_types id_roles
        id_roles.map do |role|
          next if role.fact_type.kind_of?(ActiveFacts::Metamodel::TypeInheritance)
          if !role.fact_type.entity_type && role.fact_type.all_role.size == 1
            "Boolean"
          else
           role.object_type.name.words.titlecase
          end
        end.compact
      end

      def all_identifying_roles(o)
        pis = []
        # This places the subtype identifying roles before the supertype's. Reverse the list to change this.
        id_roles = []
        o.supertypes_transitive.each do |supertype|
          pi = supertype.preferred_identifier
          next if pis.include?(pi)   # Seen this identifier already?
          pis << pi
          identifying_role_refs = pi.role_sequence.all_role_ref_in_order
          identifying_role_refs.each do |id_role_ref|
            # Have we seen this role in another identifier?
            next if id_roles.detect{|idr| idr == id_role_ref.role }
            id_roles << id_role_ref.role
          end
        end
        [id_roles, pis]
      end

      def entity_object(o, title_name, id_names, id_types)
        puts o.scala_object(title_name, id_names, id_types)
      end

      def entity_trait(o, title_name, primary_supertype, pis)
        puts o.scala_trait(title_name, primary_supertype, pis)
      end

      def entity_model(o, title_name)
        @metamodel << o.scala_metamodel(title_name)
      end

      def non_subtype_dump(o, pi)
        subtype_dump(o, nil, pi)
      end

      def subtype_dump(o, supertypes, pi = nil)
        if supertypes
          primary_supertype = o && (o.identifying_supertype || o.supertypes[0])
        end
        title_name = o.name.words.titlecase

        id_roles, pis = *all_identifying_roles(o)
        id_names = id_role_names(o, id_roles)
        id_types = id_role_types(id_roles)
        identification = pi ? identified_by(o, pi) : nil

        # REVISIT: We don't want an object for abstract classes,
        # i.e. where subtypes have a disjoint mandatory constraint
        entity_object(o, title_name, id_names, id_types)

        entity_trait(o, title_name, primary_supertype, pis)

        entity_model(o, title_name)

        @constraints_used[pi] = true if pi
      end

      def identified_by_roles_and_facts(entity_type, identifying_role_refs, identifying_facts)
        identifying_role_refs.map do |role_ref|
            [ role_ref.role.scala_preferred_role_name(entity_type),
              entity_type.name.words.titlecase
            ]
          end
      end

      def skip_fact_type(f)
        f.is_a?(ActiveFacts::Metamodel::TypeInheritance)
      end

      # Dump one fact type.
      def fact_type_dump(fact_type, name)
        @fact_types_dumped[fact_type] = true
        return objectified_fact_type_dump(fact_type.entity_type) if fact_type.entity_type

        puts fact_type.scala_definition

        @metamodel << fact_type.scala_metamodel
      end

      def objectified_fact_type_dump o
        puts o.scala_objectification
        @metamodel << o.scala_objectification_metamodel
      end

      def unary_dump(role, role_name)
        scala_role_name = role_name.words.camelcase
        puts "    val #{scala_role_name}: Boolean"
      end

      def role_dump(role)
        puts role.scala_role_definition
      end

    end
  end
end

ActiveFacts::Registry.generator('scala', ActiveFacts::Generators::Scala)

