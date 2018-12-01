"""
    getfiles(tuvdir)

Retrieve rxn files and files with the subroutine calls stored in `tuvdir/SRC/RXN`
and return as vectors of strings.
"""
function getfiles(tuvdir)
  tuvdir = abspath(tuvdir)
  cd(joinpath(tuvdir, "SRC/RXN"))
  tuvfiles = readdir()
  deleteat!(tuvfiles,findall(endswith.(tuvfiles, ".o")))
  callfiles = deepcopy(tuvfiles)
  deleteat!(callfiles,findall(startswith.(callfiles, "rxn")))
  rxnfiles = setdiff(tuvfiles, callfiles)
  return rxnfiles, callfiles, tuvdir
end #function getfiles


"""
    generate_rxns(rxnfiles, callfiles)

From the `rxnfiles` with the reaction subroutines and the `callfiles` with the
subroutine call of the reaction routines, generate a vector of strings holding
all reaction labels in the order needed for the input files and return it.
"""
function generate_rxns(rxnfiles, callfiles)
  # Initialise
  rxnlist = String[]

  # Get list of subroutines and associated reactions
  rxns = findrxnlabel(rxnfiles)
  # Get order the subroutines calls = order of reactions in input files
  order = getorder(callfiles)

  # Save O2 reaction label from swchem.f
  lines = readfile("swchem.f")
  iO2 = findfirst([occursin(r"^[ \t]*jlabel"i, line) for line in lines])
  O2rxn = replace(lines[iO2], r"^(.*?)(\'|\")" => "")
  O2rxn = strip(replace(O2rxn, r"(\'|\").*" => ""))
  push!(rxnlist, O2rxn)

  # Save reaction labels from rxn files in order
  for SR in order
    rxnlist = vcat(rxnlist, rxns[SR])
  end
  # Return String vector with reaction list
  return rxnlist
end


"""
    findrxnlabel(filelist)

Use regex search to find all subroutine names and reaction labels in the `filelist`
with the rxn files and return a dictionary with routine names as keys and the
associated reaction labels in order as entries.
"""
function findrxnlabel(filelist)
  # Initialise dictionary with subroutines and their associated reactions
  labels = Dict{String, Vector{SubString{String}}}()

  # Loop over rxn files
  for file in filelist
    # Read file
    lines = readfile(file)
    # Find lines with subroutine names and reaction lables
    isubs = findall([occursin(r"^[ \t]*subroutine"i, line) for line in lines])
    irxns = findall([occursin(r"^[ \t]*jlabel"i, line) for line in lines])

    # Save subroutine names
    # subs = [replace(line, r"^.*subroutine"i => "") for line in lines[isubs]]
    # subs = [strip(replace(line, r"\(.*"i => "")) for line in subs]
    subs = [strip(match(r"(?<=subroutine).*?(?=\()"i, rxn).match) for rxn in lines[isubs]]

    # Save reaction labels
    rxns = [match(r"(?<=\"|\').*(?=\"|\')"i, rxn).match for rxn in lines[irxns]]

    # Add index for end of file
    push!(isubs, length(lines))

    # Attribute reactions to their subroutines and save in a dictionary
    for i = 1:length(subs)
      ilab = findall(isubs[i] .< irxns .< isubs[i+1])
      labels[subs[i]] = rxns[ilab]
    end
  end

  return labels
end #function findrxnlabel


"""
    getorder(filelist)

Find out the order in which rxn subroutines are called from the `filelist` with
the files with subroutine calls and return a vector of strings with the subroutine
names in the order they are called.
"""
function getorder(filelist)
  # Initialise array with order of calls
  callorder = String[]

  # Loop over input files in reverse alphabetical order (as they are called in TUV)
  for file in reverse(sort(filelist))
    # Read files
    lines = readfile(file)
    # Find subroutine names in order
    isubs = findall([occursin(r"^[ \t]*call"i, line) for line in lines])
    subs = [replace(line, r"^.*call"i => "") for line in lines[isubs]]
    subs = [strip(replace(line, r"\(.*"i => "")) for line in subs]
    # Save order
    callorder = vcat(callorder, subs)
  end

  return callorder
end #function getorder #function generate_rxns


"""
    write_rxns(filelist, tuvdir, rxnlist, setflags)

Rewrite the reaction part in TUV input files specified in `filelist` (by default
all files are rewritten) using information from the rxn files and files with function
calls stored in `rxnlist` for TUV in the directory `tuvdir`.
TUV flags can be overwritten according to `setflags`:
- `0`: Set all flags to `F`
- `1`: Set all flags to `T`
- `2`: Set reactions used in MCM/GECKO-A to `T`, all other to `F`
- `3`: Set reactions used in MCMv3.3.1 `T`, all other to `F`
"""
function write_rxns(filelist, tuvdir, rxnlist, setflags)
  # Got to input folder
  cd(joinpath(tuvdir, "INPUTS"))
  # Derive file list, if not set by kwarg
  if filelist == ""
    filelist = readdir()
    deleteat!(filelist,findall(startswith.(filelist, ".")))
  elseif filelist isa String
    filelist = [filelist]
  end
  # Set flags, if not default
  flags = set_flags(setflags, rxnlist)
  # Loop over files
  for file in filelist
    # Read input file, and find mechanism section and number of output reactions
    lines = readfile(file)
    istart = findfirst(occursin.("photolysis reactions", lines))
    iend   = findlast(startswith.(lines, "==="))
    inmj   = findfirst(occursin.("nmj", lines))

    # Save flags, if default
    flags = set_flags(setflags, rxnlist, istart, iend, lines)

    # Auto-generate output
    lines[inmj] = @sprintf("%s%3d", lines[inmj][1:end-3], length(findall(flags.=='T')))
    open(file, "w+") do f
      [println(f, line) for line in lines[1:istart]]
      [@printf(f, "%s%3d %s\n", flags[i], collect(1:length(rxnlist))[i], rxnlist[i])
        for i = 1:length(rxnlist)]
      [println(f, line) for line in lines[iend:end]]
    end
  end
end #function write_rxns


"""
    set_flags(setflags, rxnlist, istart::Int64=0, iend::Int64=0, lines::Vector{String}=String[])

Set flags according to `setflags` option for reactios in the `rxnlist`.
For the default `setflags` option to leave flags unchagend, additionally the file
content of the current TUV file `lines`, and the beginning `istartz` and end index
`iend` of the mechanism section is needed.

The following `setflags` options exist (default: use from original input file):
- `0`: Set all flags to `F`
- `1`: Set all flags to `T`
- `2`: Set reactions used in MCM/GECKO-A to `T`, all other to `F`
- `3`: Set reactions used in MCMv3.3.1 `T`, all other to `F`
"""
function set_flags(setflags, rxnlist, istart::Int64=0, iend::Int64=0,
                  lines::Vector{String}=String[])
  # Use existing flags
  if setflags < 0
    flags = [line[1]  for line in lines[istart+1:iend-1]]
    if length(flags) < length(rxnlist)
      [push!(flags, 'T') for i = 1:1+length(rxnlist) - length(flags)]
      println("\033[95mWarning! Less flags in input file defined ",
        "than needed for current mechanism.\n\33[0m",
        "Last $(1+length(rxnlist) - length(flags)) flags set to true.")
    elseif length(flags) > length(rxnlist)
      println("\033[95mWarning! More flags in input file defined ",
        "than needed for current mechanism.\n\33[0m",
        "Last $(1+length(rxnlist) - length(flags)) flags ignored.")
      deleteat!(flags, 1+length(rxnlist) - length(flags):length(rxnlist))
    end
    return flags
  end

  # Reset flags according to setflags option
  flags = Vector{Char}(undef, length(rxnlist))
  if setflags == 0
    flags .= 'F'
  elseif setflags == 1
    flags .= 'T'
  elseif setflags > 1
    if setflags == 2
      mcm = read_data(joinpath(@__DIR__, "data/MCM-GECKO-A.db"), sep = "|",
      headerskip = 1, colnames = ["number", "label"])
    elseif setflags == 3
      mcm = read_data(joinpath(@__DIR__, "data/MCMv331.db"), sep = "|",
      headerskip = 1, colnames = ["number", "label"])
    end
    flags = Vector{Char}(undef, length(rxnlist))
    flags .= 'F'
    fail = String[]
    for rxn in mcm[:label]
      idx = findfirst(rxnlist.==rxn)
      if idx == nothing
        push!(fail, rxn)
      else
        flags[idx] = 'T'
      end
    end
    if length(fail) > 0
      println(
        "\033[95mWarning! $(length(fail)) reactions not found in MCM database:\n\33[0m",
        join(fail, "\n"))
    end
  end

  return flags
end #function set_flags


"""
    write_incfiles(rxnlist, tuvdir)

From the `rxnlist` of TUV reactions in the order of the output file and the directory
of the current TUV version `tuvdir`, write include files for the box model DSMACC
to link TUV to it and save them in the main TUV folder.
"""
function write_incfiles(rxnlist, tuvdir)
  cd(tuvdir)
  mcm32 = read_data(joinpath(@__DIR__, "data/MCMv32.db"), sep = "|",
  headerskip = 1, colnames = ["number", "SF", "label"])
  mcm33 = read_data(joinpath(@__DIR__, "data/MCMv331.db"), sep = "|",
  headerskip = 1, colnames = ["number", "label"])
  mcm4 = read_data(joinpath(@__DIR__, "data/MCM-GECKO-A.db"), sep = "|",
  headerskip = 1, colnames = ["number", "label"])
  db = [mcm32, mcm33, mcm4]
  for (i, file) in enumerate(["MCMv32.inc", "MCMv331.inc", "MCM-GECKO-A.inc"])
    open(file, "w") do f
      println(f, "  SELECT CASE (jl)")
      for (j, label) = enumerate(unique(db[i][:label]))
        tuvnumber = findfirst(rxnlist.==label)
        if tuvnumber == nothing
          println("\033[95mWarning! Reaction $label not found in TUV.\n\33[0m",
            "Reaction ignored in $file.")
        else
          @printf(f, "    CASE(%d) ! %s\n", tuvnumber, label)
          dsmaccnumber = findall(db[i][:label].==label)
          for n in dsmaccnumber
            if haskey(db[i], :SF) && db[i][:SF][n] ≠ 1
              @printf(f, "      j(%d) = seval(szabin,theta,tmp,tmp2,b,c,d)*%.3f\n",
                db[i][:number][n], db[i][:SF][n])
            else
              @printf(f, "      j(%d) = seval(szabin,theta,tmp,tmp2,b,c,d)\n",
                db[i][:number][n])
            end
          end
        end
      end # loop over reactions
      println(f, "  END SELECT")
    end # close file
  end # loop over files
end #function write_incfiles


"""
    write_wiki(rxnlist, tuvdir, ifile, ofile, len, DB, currdir)

From the `rxnlist` of TUV reactions in the order of the output file and the directory
of the current TUV version `tuvdir`, write wiki markdown files as specified by function
generate_wiki.
"""
function write_wiki(rxnlist, tuvdir, ifile, ofile, len, DB, currdir)
  # Make sure to be in the TUV main directory
  cd(tuvdir)
  ifile, ofile, len, db = init_files(ifile, ofile, len, DB, currdir)

  for i = 1:length(ifile)
    wiki = readfile(ifile[i])
    for (j, rxn) = enumerate(unique(db[i][:label]))
      n = findfirst(startswith.(wiki,rxn))
      try
        wiki[n] = @sprintf("%s | %3d | %s", rpad("J($(db[i][:number][j]))",len[i]),
          findfirst(rxnlist.==rxn), wiki[n])
      catch;
      end
    end # loop over reactions
    open(ofile[i], "w") do f
      [println(f, line) for line in wiki]
    end # close file
  end # loop over files
end #function write_wiki


"""
    init_files(ifile, ofile, len, DB, currdir)

Set up files for function write_wiki with I/O files (`ifile`/`ofile`), the column
`len`gth for markdown output, the MCM version numbers (`DB`), and the working
directory (`currdir`) to transform folder paths into absolute paths from the kwargs
of function generate_wiki.
"""
function init_files(ifile, ofile, len, DB, currdir)
  collength = Int64[]; db = []
  # Read MCM reaction numbers saved in the data files for every version
  mcm3 = read_data(joinpath(@__DIR__, "data/MCMv331.db"), sep = "|",
  headerskip = 1, colnames = ["number", "label"])
  mcm4 = read_data(joinpath(@__DIR__, "data/MCM-GECKO-A.db"), sep = "|",
  headerskip = 1, colnames = ["number", "label"])
  database = [mcm3, mcm4]
  # Make sure, all kwargs are vectors
  if ifile isa String  ifile = [ifile]  end
  if ofile isa String  ofile = [ofile]  end
  if length(ifile) ≠ length(ofile)
    println("\033[95mError! Different number of input and output files specified.")
    println("Julia stopped.\033[0m")
  end
  if len isa Number
    [push!(collength, len) for i = 1:length(ifile)]
  else
    collength = len
  end
  # Convert input paths to absolute folder paths
  for i = 1:length(ifile)
    if !isabspath(ifile[i])  ifile[i] = normpath(joinpath(currdir, ifile[i]))  end
    if !isabspath(ofile[i])  ofile[i] = normpath(joinpath(currdir, ofile[i]))  end
  end
  # Set up database with MCM/GECKO-A reaction numbers for correct MCM version
  [push!(db, database[i-2]) for i in DB]

  return ifile, ofile, collength, db
end
