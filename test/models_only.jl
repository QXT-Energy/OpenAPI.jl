@testset "models-only generation" begin
    document = Dict(
        "openapi" => "3.1.0",
        "info" => Dict("title" => "Pets", "version" => "1"),
        "paths" => Dict(
            "/pets/{id}" => Dict(
                "get" => Dict(
                    "operationId" => "getPet",
                    "parameters" => Any[Dict(
                        "name" => "id",
                        "in" => "path",
                        "required" => true,
                        "schema" => Dict("type" => "integer"),
                    )],
                    "responses" => Dict(
                        "200" => Dict(
                            "description" => "ok",
                            "content" => Dict(
                                "application/json" => Dict(
                                    "schema" => Dict(
                                        "\$ref" => "#/components/schemas/Pet",
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "components" => Dict(
            "schemas" => Dict(
                "Pet" => Dict(
                    "type" => "object",
                    "required" => Any["name"],
                    "properties" => Dict(
                        "name" => Dict("type" => "string"),
                        "age" => Dict("type" => "integer", "minimum" => 0),
                    ),
                ),
            ),
        ),
    )

    @test_throws ArgumentError OpenAPI.client(document; models_only = true)

    mktempdir() do dir
        path = joinpath(dir, "src", "PetModels.jl")
        source = OpenAPI.client(document; name = "PetModels", path, models_only = true)
        @test read(path, String) == source
        @test !occursin("HTTP", source)
        @test !occursin("Client", source)
        @test !occursin("getPet", source)
        schema_files = readdir(joinpath(dir, "src", "schemas"))
        @test !isempty(schema_files)
        @test all(endswith(".json"), schema_files)
        @test occursin("_schema_resource(", source)

        host = Module(:PetModelsHost)
        Base.include(host, path)
        C = Base.invokelatest(getfield, host, :PetModels)
        lookup(name) = Base.invokelatest(getfield, C, name)
        defined(name) = Base.invokelatest(isdefined, C, name)
        @test !defined(:Client)
        @test !defined(:DEFAULT_CLIENT)
        @test !defined(:server!)
        @test !defined(:getpet)
        call(name, args...) = Base.invokelatest(lookup(name), args...)
        Pet = lookup(:Pet)
        SchemaValidationError = lookup(:SchemaValidationError)

        pet = call(:_decode, Pet, Dict("name" => "Rex", "age" => 3))
        @test pet.name == "Rex"
        @test call(:_encode, pet) == Dict("name" => "Rex", "age" => 3)
        invalid = Dict("name" => "Rex", "age" => -1)
        @test_throws SchemaValidationError call(:_decode, Pet, invalid)
        @test call(:_decode, Pet, invalid, false).age == -1

        # A second run replaces the schema files.
        OpenAPI.client(document; name = "PetModels", path, models_only = true)
        @test readdir(joinpath(dir, "src", "schemas")) == schema_files
    end

    default_source = OpenAPI.client(document; name = "PetClient")
    @test occursin("using HTTP", default_source)
    @test occursin("DEFAULT_CLIENT", default_source)
    @test !occursin("_schema_resource(", default_source)
end

@testset "models-only schema file names" begin
    function spec(refs)
        return Dict(
            "openapi" => "3.1.0",
            "info" => Dict("title" => "Zoo", "version" => "1"),
            "paths" => Dict(),
            "components" => Dict(
                "schemas" => Dict(
                    "Zoo" => Dict(
                        "type" => "object",
                        "properties" => Dict(
                            "pet" => Dict("\$ref" => refs[1]),
                            "owner" => Dict("\$ref" => refs[2]),
                        ),
                    ),
                ),
            ),
        )
    end
    object(field) = Dict(
        "type" => "object",
        "properties" => Dict(field => Dict("type" => "string")),
    )

    mktempdir() do dir
        mkpath(joinpath(dir, "in"))
        write(joinpath(dir, "in", "Pet.json"), JSON.json(object("name")))
        write(joinpath(dir, "in", "Owner.json"), JSON.json(object("email")))
        write(joinpath(dir, "in", "zoo.json"), JSON.json(spec(["Pet.json", "Owner.json"])))
        path = joinpath(dir, "out", "Zoo.jl")
        mkpath(dirname(path))
        OpenAPI.client(joinpath(dir, "in", "zoo.json"); name = "Zoo", path, models_only = true)
        @test readdir(joinpath(dir, "out", "schemas")) == ["Owner.json", "Pet.json", "zoo.json"]
        source = read(path, String)
        @test occursin("_schema_resource(\"Pet.json\")", source)
        @test occursin("_schema_resource(\"zoo.json\")", source)
        # The resource ids stay portable.
        @test occursin("https://openapi.invalid/schema/", source)

        # An inline spec keeps the id-based names.
        inline_path = joinpath(dir, "out2", "Zoo.jl")
        mkpath(dirname(inline_path))
        OpenAPI.client(
            JSON.json(spec(["file://" * joinpath(dir, "in", "Pet.json"), "file://" * joinpath(dir, "in", "Owner.json")]));
            name = "Zoo",
            path = inline_path,
            models_only = true,
            file_roots = [dir],
        )
        @test sort(readdir(joinpath(dir, "out2", "schemas"))) ==
              ["Owner.json", "Pet.json", "root.json"]
    end

    mktempdir() do dir
        mkpath(joinpath(dir, "a"))
        mkpath(joinpath(dir, "b"))
        write(joinpath(dir, "a", "Pet.json"), JSON.json(object("name")))
        write(joinpath(dir, "b", "Pet.json"), JSON.json(object("tag")))
        write(
            joinpath(dir, "zoo.json"),
            JSON.json(spec(["a/Pet.json", "b/Pet.json"])),
        )
        path = joinpath(dir, "out", "Zoo.jl")
        mkpath(dirname(path))
        error = try
            OpenAPI.client(joinpath(dir, "zoo.json"); name = "Zoo", path, models_only = true)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin(joinpath(dir, "a", "Pet.json"), error.msg)
        @test occursin(joinpath(dir, "b", "Pet.json"), error.msg)
    end
end
