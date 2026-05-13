"""
Learning is creating a Pkg once the code is good.
The Pkg is added to a local registry
"""
module TOGLearning

# todo handle fails

export update, newpkg, updatepkg, cppkg

using Pkg, TOML, LocalRegistry, Git, GitHub
using Pkg.Types: PackageSpec, Context

const REGISTRYNAME = "TOGRegistry"
const JULIACODEPATH = joinpath(DEPOT_PATH[1], "dev")

const LICENSEFILE = "LICENSE"
const LICENSE = """
Study it, use it, enjoy it.
Any one deriving value from this should share a fair value >= 0.
"""
const READMEFILE = "README.md"
const README(name) = "# $name"
const GITIGNOREFILE = ".gitignore"
const GITIGNORE = """
.*
Manifest.toml
tmp*
"""

pkgdir(;name) = joinpath(JULIACODEPATH, name)
projecttoml(;name) = joinpath(pkgdir(name=name), "Project.toml")
# registrytoml() = joinpath(LOOPOSREGISTRYPATH, "Registry.toml")

"""
pkgs: Pkgs to be added (via name, url, path).
files: Files to be copied over.
"""
function newpkg(; name::String, files=String[], pkgs=String[], githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    path = pkgdir(name=name)
    Pkg.generate(path)
    try
        changefiles(name=name, files=files, rmfiles=String[], cpmv=mvfiles ? mv : cp)
        changepkgs(name=name, pkgs=pkgs, rmpkgs=String[])
        initversion(name=name)
        addcommit(path=path)
        newremoterepo(path=path, githubuser=githubuser, githubauth=githubauth)
        registerpkg(name=name)
    catch e
        rm(path, force=true, recursive=true)
        rethrow(e)
    end
end

"""
pkgs: new Pkgs to be added
rmpkgs: Pkgs to be removed
files: Files to be copied over
rmfiles: Files to be removed
"""
function updatepkg(; name::String, files=String[], pkgs=String[], rmfiles=String[], rmpkgs=String[], githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    changefiles(name=name, files=files, rmfiles=rmfiles, cpmv=mvfiles ? mv : cp)
    changepkgs(name=name, pkgs=pkgs, rmpkgs=rmpkgs)
    updateversion(name=name)
    path = pkgdir(name=name)
    addcommit(path=path)
    if hasremote(path=path)
        pushremote(path=path)
    else
        newremoterepo(path=path, githubuser=githubuser, githubauth=githubauth)
    end
    registerpkg(name=name)
end
# function rmpkg(; name::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
# rmdir(joinpath(JULIACODEPATH, name))
# path = registrytoml()
# registry = TOML.parsefile(path)
# pkgkeys = filter(k -> registry["packages"][k]["name"] == name, keys(registry["packages"]))
# if !isempty(pkgkeys)
# pkgkey = only(pkgkeys)
# rmdir(joinpath(LOOPOSREGISTRYPATH, registry["packages"][pkgkey]["path"]))
# delete!(registry["packages"], pkgkey)
# open(path, "w") do io
# TOML.print(io, registry)
# end
# addcommitpush(LOOPOSREGISTRYPATH, push=pushregistry)
# end
# rmrepo(name, githubuser, githubauth)
# end
function cppkg(; name::String, newname::String, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    files = readdir(joinpath(pkgdir(name=name), "src"), join=true)
    project = TOML.parsefile(projecttoml(name=name))
    pkgs = haskey(project, "deps") ? collect(keys(project["deps"])) : String[]
    newpkg(name=newname, files=files, pkgs=pkgs, githubuser=githubuser, githubauth=githubauth)
end
# function mvpkg(; name::String, newname::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
#     cppkg(name=name, newname=newname, pushregistry=pushregistry, githubuser=githubuser, githubauth=githubauth)
#     rmpkg(name=name)
# end

# rmdir(path) = isdir(path) && rm(path, recursive=true)
function addfile(; name, file, content)
    file = joinpath(pkgdir(name=name), file)
    !isfile(file) && write(file, content)
end
srcfile(; name, file) = joinpath(pkgdir(name=name), "src", basename(file))
function changefiles(; name, files, rmfiles, cpmv)
    addfile(name=name, file=LICENSEFILE, content=LICENSE)
    addfile(name=name, file=GITIGNOREFILE, content=GITIGNORE)
    addfile(name=name, file=READMEFILE, content=README(name))
    for file = files
        cpmv(file, srcfile(name=name, file=file), force=true)
    end
    for file = rmfiles
        rm(srcfile(name=name, file=file))
    end
end

# function rmcompat()
#     path = projecttoml(pkg)
#     project = TOML.parsefile(path)
#     delete!(project, "compat")
#     open(path, "w") do file
#         TOML.print(file, project)
#     end
# end
# function updatecompat(; pkg)
#     ctx = Pkg.Types.Context()
#     pkgname = pkg
#     if startswith(pkg, "http")
#         for (_, entry) in ctx.env.manifest
#             entry.repo.source == pkg && (pkgname = entry.name)
#         end
#     end
#     version = v"0"
#     for (_, entry) in ctx.env.manifest
#         entry.name == pkgname && (version = entry.version)
#     end
#     Pkg.compat(pkgname, ">=$version")
# end
function changepkg(pkg, f)
    if startswith(pkg, "http")
        f(url=pkg)
    elseif ispath(pkg)
        f(path=pkg)
    else
        f(pkg)
    end
end
function changepkgs(; name, pkgs, rmpkgs)
    cd(pkgdir(name=name)) do
        oldenv = Base.active_project()
        Pkg.activate(".")
        isempty(pkgs) || Pkg.add(pkgs)
        isempty(rmpkgs) || Pkg.rm(rmpkgs)
        Pkg.activate(oldenv)
    end
end

function registerpkg(; name)
    try
        register(
            pkgdir(name=name),
            registry=REGISTRYNAME,
            push=true
        )
    catch
        register(
            pkgdir(name=name),
            registry=REGISTRYNAME,
            push=false
        )
    end
end

function resolve(; name)
    cd(pkgdir(name=name)) do
        oldenv = Base.active_project()
        Pkg.activate(".")
        Pkg.resolve()
        Pkg.activate(oldenv)
    end
end
function changeversion(; name, newversion)
    path = projecttoml(name=name)
    project = TOML.parsefile(path)
    version = VersionNumber(project["version"])
    project["version"] = string(newversion(version))
    delete!(project, "compat")
    open(path, "w") do file
        TOML.print(file, project)
    end
    resolve(name=name)
    project["version"]
end
initversion(; name) = changeversion(name=name, newversion=_ -> v"1")
updateversion(; name) = changeversion(name=name, newversion=v -> VersionNumber(v.major + 1))

isdirty(; path=".") =
    cd(path) do
        !isempty(read(`$(git()) status --porcelain`))
    end
remoteurl(; name, githubuser=get(ENV, "GITHUB_USER", "")) = """https://github.com/$githubuser/$name.git"""
# remoteurl(; name, githubuser=get(ENV, "GITHUB_USER", "")) = """git@github.com:$githubuser/$name.git"""
# remoteurl(; name, githubuser=get(ENV, "GITHUB_USER", "")) = joinpath(JULIACODEPATH, name)
hasremote(; path=".") =
    cd(path) do
        !isempty(readlines(`$(git()) remote`))
    end
getremoteurl(; path=".") =
    cd(path) do
        readline(`$(git()) remote get-url origin`)
    end
addsetremote(; path, addset, githubuser=get(ENV, "GITHUB_USER", "")) =
    cd(path) do
        run(`$(git()) remote $addset origin $(remoteurl(name=basename(path), githubuser=githubuser))`)
    end
addremote(; path, githubuser=get(ENV, "GITHUB_USER", "")) = addsetremote(path=path, githubuser=githubuser, addset="add")
setremote(; path, githubuser=get(ENV, "GITHUB_USER", "")) = addsetremote(path=path, githubuser=githubuser, addset="set-url")
pushremote(; path=".", githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", "")) =
    cd(path) do
        url = getremoteurl()
        url = replace(url, "https://" => "https://$githubuser:$githubauth@")
        run(`$(git()) push $url main`)
    end
function addcommit(; path, commitmessage=".")
    cd(path) do
        isnew = !isdir(".git")
        isnew && run(`$(git()) init`)
        run(`$(git()) add .`)
        !isnew && !isdirty(path=".") && return
        run(`$(git()) commit -m $commitmessage`)
    end
end
function newremoterepo(; path, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    !isempty(githubuser) && addremote(path=path, githubuser=githubuser)
    if !isempty(githubuser) && !isempty(githubauth)
        create_repo(
            GitHub.owner(githubuser),
            basename(path),
            auth=authenticate(githubauth),
        )
        pushremote(path=path)
    end
end
remoterepoexists(; name, githubuser=get(ENV, "GITHUB_USER", "")) =
    try
        true, repo("$githubuser/$name")
    catch
        false, nothing
    end
function rmremoterepo(; name, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    if !isempty(githubuser) && !isempty(githubauth)
        exists, repo = remoterepoexists(name=name, githubuser=githubuser)
        exists && delete_repo(
            repo,
            auth=authenticate(githubauth),
        )
    end
end

end
