#
#       ActiveFacts Generators.
#
# Metamodel Traits for mapping to Scala
#
# Copyright (c) 2009 Clifford Heath. Read the LICENSE file.
#
module ActiveFacts
  module Generators
    module ScalaTraits
      module Vocabulary
        def scala_prelude
          title_name = name.words.titlecase

          "package model\n"+
          "\n"+
          "import scala.language.implicitConversions\n" +
          "\n" +
          "object #{title_name} extends LocalStorageConstellation with #{title_name}\n" +
          "\n" +
          "trait #{title_name} extends Model {\n" +
          # REVISIT: I think this next line should be model, not metaModel
          "  val metaModel = new #{title_name}Model()\n" +
          "\n"
        end

        def scala_prelude_metamodel
          title_name = name.words.titlecase
          "class #{title_name}Model extends FBMModel with LocalStorageConstellation {\n" +
          "  implicit val constellation: Constellation = this\n"
        end

        def scala_finale
          "}\n"+
          "\n"
        end
      end

      module ObjectType
        # Map the ObjectType name to a Scala class name
        def scala_type_name
          oo_type_name
        end

        # Map the Scala class name to a default role name
        def scala_default_role_name
          oo_default_role_name
        end

        def absorbed_roles
          all_role.
            select do |role|
              role.fact_type.all_role.size <= 2 &&
                !role.fact_type.is_a?(ActiveFacts::Metamodel::LinkFactType)
            end.
            sort_by do |role|
              r = role.fact_type.all_role.select{|r2| r2 != role}[0] || role
              r.scala_preferred_role_name(self) + ':' + role.scala_preferred_role_name(r.object_type)
            end
        end
      end

      module Role
        def scala_preferred_role_name(is_for = nil, &name_builder)
          # REVISIT: Modify this to suit Scala

          if fact_type.is_a?(ActiveFacts::Metamodel::TypeInheritance)
            # Subtype and Supertype roles default to TitleCase names, and have no role_name to worry about:
            return (name_builder || proc {|names| names.titlecase}).call(object_type.name.words)
          end

          name_builder ||= proc {|names| names.map(&:downcase)*'_' }   # Make snake_case by default

          # Handle an objectified unary role:
          if is_for && fact_type.entity_type == is_for && fact_type.all_role.size == 1
            return name_builder.call(object_type.name.words)
          end

          # trace "Looking for preferred_role_name of #{describe_fact_type(fact_type, self)}"
          reading = fact_type.preferred_reading
          preferred_role_ref = reading.role_sequence.all_role_ref.detect{|reading_rr|
              reading_rr.role == self
            }

          if fact_type.all_role.size == 1
            return name_builder.call(
              role_name ?
                role_name.snakewords :
                reading.text.gsub(/ *\{0\} */,' ').gsub(/[- ]+/,'_').words
            )
          end

          if role_name && role_name != ""
            role_words = [role_name]
          else
            role_words = []

            la = preferred_role_ref.leading_adjective
            role_words += la.words.snakewords if la && la != ""

            role_words += object_type.name.words.snakewords

            ta = preferred_role_ref.trailing_adjective
            role_words += ta.words.snakewords if ta && ta != ""
          end

          # n = role_words.map{|w| w.gsub(/([a-z])([A-Z]+)/,'\1_\2').downcase}*"_"
          n = role_words*'_'
          # trace "\tresult=#{n}"
          return name_builder.call(n.gsub(' ','_').split(/_/))
        end

        def scala_role_definition
          return if fact_type.entity_type

          if fact_type.all_role.size == 1
            scala_role_name = scala_preferred_role_name.words.camelcase
            return "    val #{scala_role_name}: Boolean"
          elsif fact_type.all_role.size != 2
            # Shouldn't come here, except perhaps for an invalid model
            return  # ternaries and higher are always objectified
          end

          return if fact_type.is_a?(ActiveFacts::Metamodel::TypeInheritance)

          other_role = fact_type.all_role.select{|r| r != self}[0]
          other_role_name = other_role.scala_preferred_role_name
          scala_role_name = other_role_name.words.camelcase
          other_type_name = other_role.object_type.name.words.titlecase

          if is_functional
            if is_mandatory
              # Define a getter for a mandatory value:
              "    val #{scala_role_name}: #{other_type_name}"
              if !fact_type.is_existential
                "    def #{scala_role_name}_=(_value: #{other_type_name}) = { #{scala_role_name} = _value }"
              end
            else
              # Define a getter for an optional value:
              # REVISIT: The role number here depends on the metamodel ordering of the fact type roles.
              # This likely should follow the role order of the preferred reading, from which the fact name is derived.
              # The code here collows the order of definition of the roles in the fact type,
              # which might not be the same as the order of the preferred reading:
              fact_name = fact_type.scala_name.titlecase
              role_number = fact_type.all_role_in_order.index(other_role)+1

              "    def #{scala_role_name}: Option[#{other_type_name}] = {\n" +
              "      constellation.getBinaryFact(metaModel.#{fact_name.words.camelcase}, this).map(x => {\n" +
              "        x.head.asInstanceOf[FBMModel.BinaryFact].rolePlayers._#{role_number}.asInstanceOf[#{other_type_name}]\n" +
              "      })\n" +
              "    }\n" +
              if !fact_type.is_existential
                # Define a setter for an optional value:
                "    def #{scala_role_name}_=(value: Option[#{other_type_name}]) = {\n" +
                "      value match {\n" +
                "        case None =>\n" +
                "        case Some(m) => constellation.assertBinaryFact(#{fact_name.words.titlecase}(this, m))\n" +
                "      }\n" +
                "    }"
              else
                ''
              end
            end
          elsif other_role.object_type.fact_type
            # An objectified fact type
            <<"END"
      def all#{scala_role_name.words.titlecase}(implicit constellation: Constellation): Seq[#{other_type_name}] = {
        constellation.getObjectifiedFact(metaModel.#{scala_role_name.words.camelcase}, this).getOrElse(Nil).flatMap(x => x match {
          case o: #{other_type_name} => Some(o)
          case _ => None
        })
      }
END
          else
            <<"END"
      /*
      def all#{scala_role_name.words.titlecase}(implicit constellation: Constellation): Seq[#{other_type_name}] = {
        constellation.getFact(metaModel.#{scala_role_name.words.camelcase}, this).getOrElse(Nil).flatMap(x => x match {
          # REVISIT: This is incorrect; we want to return the other role player in the fact
          case o: #{other_type_name} => Some(o)
          case _ => None
        })
      }
      */
END
          end
        end
      end

      module ValueType
        DataTypeMap = {
          "Signed Integer" => "Int",
          "Unsigned Integer" => "Int",
          "Real" => "Double",
          "Char" => "String",
          # REVISIT: More will be needed here.
        }
        LengthTypes = [ "String", "Decimal" ]
        ScaleTypes = [ "Decimal" ]

        def scala_definition(super_type_name, facets)
          vt_name = name.words.titlecase
          if d = DataTypeMap[super_type_name]
            super_type_name = d
          end
          super_type_title = super_type_name.words.titlecase
          super_type_camel = super_type_name.words.camelcase

          sometimes_optional =  all_role.detect do |r|
            r.fact_type.all_role.size == 2 && (c = (r.fact_type.all_role.to_a-[r])[0]) and !c.is_mandatory
          end

          "  case class #{vt_name}(value: #{super_type_title})(implicit val constellation: Constellation) extends FBMModel.ValueTypeValue[#{super_type_title}] {\n" +
          "    val objectType = metaModel.#{vt_name.words.camelcase}\n" +
#         REVISIT: scala_type_params +
#         REVISIT: scala_value_restriction + # puts "    restrict #{value_constraint.all_allowed_range_sorted.map{|ar| ar.to_s}*", "}\n" if value_constraint
#         REVISIT: scala_units +  # puts "    \# REVISIT: #{vt_name} is in units of #{unit.name}\n" if unit
          absorbed_roles.map do |role|
            role.scala_role_definition
          end.
          compact*"\n" +
          "  }\n" +

          # Add implicit casts for the underlying data type:
          "  implicit def #{super_type_camel}2#{vt_name}(value: #{super_type_title})(implicit constellation: Constellation): #{vt_name} = #{vt_name}(value)\n" +
          if sometimes_optional
            "  implicit def #{super_type_camel}2#{vt_name}Option(value: #{super_type_title})(implicit constellation: Constellation): Option[#{vt_name}] = Some(#{vt_name}(value))\n"
          else
            ""
          end +
          "\n"
        end

        def scala_metamodel(super_type_name, facets)
          vt_name = name.words.titlecase
          super_type_title = super_type_name.words.titlecase
          # REVISIT: Remove facets that do not apply to the Scala data types
          params = [
            LengthTypes.include?(super_type_name) ? facets[:length] : nil,
            ScaleTypes.include?(super_type_name) ? facets[:scale] : nil
          ].compact * ", "

          "  val #{name.words.camelcase} = assertEntity(FBMModel.ValueType(FBMModel.DomainObjectTypeName(\"#{vt_name}\"), FBMModel.#{super_type_title}Type(#{params}), Nil))\n"
        end
      end

      module EntityType
        def scala_object(title_name, id_names, id_types)
          "  object #{title_name} {\n" +
          "    def apply(" +
            (id_names.zip(id_types).map do |(name, type_name)|
              "#{name}: #{type_name}"
            end * ', '
            ) +
          ")(implicit constellation: Constellation) = {\n" +

          # Define the constant storage for the identifying role values:
          id_names.map do |name|
            "      val _#{name} = #{name}"
          end*"\n" +
          "      val _constellation = constellation\n" +
          "      assertEntity(new #{title_name} {\n" +
            id_names.map do |name|
              "        val #{name} = _#{name}"
            end*"\n" +
          "        val constellation = _constellation\n" +
          "      })\n" +        # Ends new block and assertEntity
          "    }\n" +           # Ends apply()
          "  }\n" +             # Ends object{} 
          "\n"
        end

        def scala_trait(title_name, primary_supertype, pis)
          s = 'override ' unless supertypes.empty?

          "  trait #{title_name} extends #{primary_supertype ? primary_supertype.name.words.titlecase : 'FBMModel.Entity'} {\n" +
          "    #{s}val objectType = metaModel.#{name.words.camelcase}\n" +
          (fact_type ? "  // REVISIT: Here, we should use fact_roles_dump(fact_type)\n\n" : '') +
          absorbed_roles.map do |role|
            role.scala_role_definition
          end.
          compact*"\n" +
          "    #{s}val identifier: Seq[Seq[FBMModel.Identifier[_]]] = Seq(#{
            pis.map do |pi|
              'Seq(' +
                pi.role_sequence.all_role_ref_in_order.map do |id_role_ref|
                  id_role_ref.role.object_type.name.words.camelcase
                end*', ' +
              ')'
            end*', '
          })\n" +
          "  }\n" +             # Ends trait{}
          "\n"
        end

        def scala_metamodel(title_name)
          pi = preferred_identifier
          # The following finds the closest non-inheritance identifier
          #while pi.role_sequence.all_role_ref.size == 1 and
          #    (role = pi.role_sequence.all_role_ref.single.role).fact_type.is_a?(ActiveFacts::Metamodel::TypeInheritance)
          #  pi = role.fact_type.supertype_role.object_type.preferred_identifier
          #end
          identifying_parameters =
            pi.role_sequence.all_role_ref_in_order.map{|rr| rr.role.object_type.name.words.camelcase }*', '

          supertypes_list =
            if supertypes.empty?
              'Nil'
            else
              "List(#{supertypes.map{|s| s.name.words.camelcase}*', '})"
            end
          "  val #{name.words.camelcase} = assertEntity(FBMModel.EntityType(FBMModel.DomainObjectTypeName(\"#{title_name}\"), #{supertypes_list}, Seq(#{identifying_parameters})))\n"
        end

        def scala_shared(o, supertypes, pi = nil)
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
          entity_object(title_name, id_names, id_types)

          entity_trait(o, title_name, primary_supertype, pis)

          entity_model(o, title_name)
        end

        def id_role_names id_roles
          id_roles.map do |role|
            # Ignore identification through a supertype
            next if role.fact_type.kind_of?(ActiveFacts::Metamodel::TypeInheritance)
            role.scala_preferred_role_name(self).words.camelcase
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

        def scala_objectification
          # REVISIT: This disregards any supertypes and their identifiers
  #       primary_supertype = o && (o.identifying_supertype || o.supertypes[0])
  #       secondary_supertypes = o.supertypes-[primary_supertype]

          pi = preferred_identifier
          id_roles = []
          identifying_role_refs = pi.role_sequence.all_role_ref_in_order
          identifying_role_refs.each do |id_role_ref|
            id_roles << id_role_ref.role
          end
          id_names = id_role_names id_roles
          id_types = id_role_types id_roles

          "  case class #{name.words.titlecase}(#{
            id_names.zip(id_types).map {|(n, t)|
              "#{n}: #{t}"
            }*', '
          }) extends FBMModel.ObjectifiedFact {\n" +
          "    // REVISIT: Here, we should use fact_roles_dump(fact_type)\n" +
          absorbed_roles.map do |role|
            role.scala_role_definition
          end.
          compact*"\n" +
          "  }"
        end

        def scala_objectification_metamodel
          identifying_parameters = preferred_identifier.role_sequence.all_role_ref_in_order.map{|rr| rr.role.object_type.name.words.camelcase }*', '
          "  val #{name.words.camelcase} = assertEntity(FBMModel.ObjectifiedType(FBMModel.DomainObjectTypeName(\"#{name.words.titlecase}\"), Nil, Seq(#{identifying_parameters})))\n"
        end
      end

      module FactType
        def scala_name
          default_reading.words
        end

        def scala_definition
          # Dump a non-objectified fact type
          name_words = scala_name
          role_names = preferred_reading.role_sequence.all_role_ref_in_order.map do |rr|
              rr.role.scala_preferred_role_name.words.camelcase
            end
          role_types = preferred_reading.role_sequence.all_role_ref_in_order.map do |rr|
              rr.role.object_type.name.words.camelcase
            end

          "  case class #{name_words.titlecase}(#{role_names.zip(role_types).map{|n, t| n+': '+t}*', '})(implicit val constellation: Constellation) extends FBMModel.BinaryFact {\n" +
          "    def factType = metaModel.#{name_words.camelcase}\n" +
          "    def rolePlayers = (#{role_names*', '})\n" +
          "  }\n\n"
        end

        def scala_metamodel
          name_words = scala_name
          role_names = preferred_reading.role_sequence.all_role_ref_in_order.map do |rr|
              rr.role.scala_preferred_role_name.words.camelcase
            end
          "  val #{name_words.camelcase} = assertEntity(FBMModel.BinaryFactType(FBMModel.FactTypeName(\"#{name_words.titlecase}\"), (#{role_names*', '})))\n"
        end

        # An objectified fact type has internal roles that are always "has_one":
        def fact_roles
          raise "Fact #{describe} type is not objectified" unless entity_type
          all_role.sort_by do |role|
            role.scala_preferred_role_name(entity_type)
          end.
          map do |role| 
            role_name = role.scala_preferred_role_name(entity_type)
            one_to_one = role.all_role_ref.detect{|rr|
              rr.role_sequence.all_role_ref.size == 1 &&
              rr.role_sequence.all_presence_constraint.detect{|pc|
                pc.max_frequency == 1
              }
            }
            counterpart_role_method = (one_to_one ? "" : "all_") + 
              entity_type.oo_default_role_name +
              (role_name != role.object_type.oo_default_role_name ? "_as_#{role_name}" : '')
            role.as_binary(role_name, role.object_type, true, one_to_one, nil, nil, counterpart_role_method)
          end.
          join('')
        end
      end

      include ActiveFacts::TraitInjector        # Must be last in this module, after all submodules have been defined
    end
  end
end
