"""
    write_wiki(rxnlist, tuvdir, ifile, ofile, len, DB, currdir)

From the `rxnlist` of TUV reactions in the order of the output file and the directory
of the current TUV version `tuvdir`, write wiki markdown files as specified by function
generate_wiki.
"""
function write_wiki(rxnlist, tuvdir, ifile, ofile, len, DB, currdir)
  # Skip routine, if no template is provided
  if ifile == ""  return  end
  # Make sure to be in the TUV main directory
  cd(tuvdir)
  ifile, ofile, len, db = init_wikifiles(ifile, ofile, len, DB, currdir)

  for i = 1:length(ifile)
    wiki = readfile(ifile[i])
    counter = 0
    for (j, rxn) = enumerate(unique(db[i][:label]))
      n = findfirst(startswith.(wiki,rxn))
      try
        wiki[n] = @sprintf("%s | %3d | %s", rpad("J($(db[i][:number][j]))",len[i]),
          findfirst(rxnlist.==rxn), wiki[n])
        counter += 1
      catch;
      end
    end # loop over reactions
    open(ofile[i], "w") do f
      [println(f, line) for line in wiki]
    end # close file
    println("Reaction numbers for $counter reactions written to $(basename(ofile[i])).")
  end # loop over files
end #function write_wiki


"""
    init_wikifiles(ifile, ofile, len, DB, currdir)

Set up files for function write_wiki with I/O files (`ifile`/`ofile`), the column
`len`gth for markdown output, the MCM version numbers (`DB`), and the working
directory (`currdir`) to transform folder paths into absolute paths from the kwargs
of function generate_wiki.
"""
function init_wikifiles(ifile, ofile, len, DB, currdir)
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
end #function init_wikifiles


"""
    write_params(ifile, ofile, pwd)

From `ifile` `parameters.csv` from repository
[MCMphotolysis](https://github.com/wacl-york/MCMphotolysis.git)
write a table of the MCM/GECKO-A photolysis parameters to a markdown file `ofile`.
Use `pwd` to determine absolute paths of the files.
"""
function write_params(ifile, ofile, pwd)
  # Skip routine, if no template is provided
  if ifile == ""  return  end
  # Determine absolute paths of I/O files
  if !isabspath(ifile)  ifile = joinpath(pwd, ifile)  end
  if !isabspath(ofile)  ofile = joinpath(pwd, ofile)  end
  # Read header of md file
  header = readfile(joinpath(@__DIR__, "data/params_header.md"))

  # Open output file
  open(ofile,"w") do f
    # print header
    [println(f, line) for line in header]
    # Read parameter file from MCMphotolysis
    param = read_data(ifile, sep = ";", header = 1)
     # Loop over reactions
    for i = 1:length(param[1])
      # Retrieve and format l parameters and errors
      la0 = format_float(param[1][i], param[8][i])
      lb0 = format_float(param[2][i], param[9][i])
      lb1 = @sprintf("%8.2f±%.2f", param[3][i], param[10][i])
      lc0 = format_float(param[4][i], param[11][i])
      lc1 = @sprintf("%8.2f±%.2f", param[5][i], param[12][i])
      # Calculate orignal l parameter at 350 DU and order of magnitude
      l = lnew(350., param[i,1:5])
      o = Int(floor(log10(abs(l))))
      lp = l/10.0^o
      # Print reaction to md file
      @printf(f, "%10s  | %3d |%30s |%30s |%s|%30s |",
        rpad(param[end-2][i],8), param[end-1][i], la0, lb0, rpad(lb1,16), lc0)
      @printf(f, "%s| %6.3f·10<sup>%d</sup> |%6.3f±%.3f |%6.3f±%.3f | %s\n",
        rpad(lc1,16),lp, o,
        param[6][i], param[13][i], param[7][i], param[14][i], param[end][i])
    end # loop over reactiojns
    # Inform about number of reactions on screen
    println("MCM/GECKO-A parameters for $(length(param[1])) reactions ",
      "written to $(basename(ofile)).")
  end # close file
end #function write_params


"""
    format_float(n::AbstractFloat, m::AbstractFloat)

Derive the order of magnitude for float `n` and return `String` in the form
`"(X.XXX±Y.YYY)·10<sup>Z</sup>"`, where `X` and `Y` are n and m reduced by the
order of magnitude of `n` and `Z` is the order of magnitude.
"""
function format_float(n::AbstractFloat, m::AbstractFloat)
  o = Int(floor(log10(abs(n))))
  @sprintf("(%.3f±%.3f)·10<sup>%d</sup>",n/10.0^o, m/10.0^o, o)
end


"""
    lnew(O3,p) / s^-1 = p[1] + p[2]·exp(-O3/p[3]) + p[4]·exp(-O3/p[5])
"""
lnew(O3,p) = (p[1]+p[2]*exp.(-O3/p[3])+p[4]*exp.(-O3/p[5]))[1]
