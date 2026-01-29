#!/bin/bash
# Create .sno files with thin initial snow layer for numerical stability

BACKUP_DIR="./snow_init_backup"
SNOW_DIR="./snow_init"

echo "Creating SNO files with 10cm initial snow layer (including fields line)..."
echo ""

# Snow layer parameters (typical fresh Antarctic snow)
SNOW_THICK=0.10           # 10cm thick
SNOW_TEMP=250.0          # -23°C (cold but reasonable)
VOL_FRAC_I=0.30          # Ice content (corresponds to ~270 kg/m3 density)
VOL_FRAC_W=0.0           # No liquid water
VOL_FRAC_V=0.70          # Air content (70% porosity)
VOL_FRAC_S=0.0           # No soil in snow
RHO_S=0                   # No soil
CONDUC_S=0
HEATCAP_S=0
RG=0.5                    # Grain radius 0.5mm (fresh snow)
RB=0.5                    # Bond radius
DD=0.0                    # Dendricity
SP=1.0                    # Sphericity
MK=0                      # Marker
MASS_HOAR=0.0
NE=1                      # Number of elements
CDOT=0.0
METAMO=0.0

count=0
for backup_file in "$BACKUP_DIR"/*.sno; do
    if [[ -f "$backup_file" ]]; then
        filename=$(basename "$backup_file")
        sno_file="$SNOW_DIR/$filename"
        
        # Copy header including fields line (23 lines), set nSoilLayerData=0, nSnowLayerData=1
        head -23 "$backup_file" | \
            sed "s/nSoilLayerData   = [0-9]*/nSoilLayerData   = 0/" | \
            sed "s/nSnowLayerData   = [0-9]*/nSnowLayerData   = 1/" > "$sno_file"
        
        # Add [DATA] section with one snow layer
        echo "[DATA]" >> "$sno_file"
        # Use ProfileDate as timestamp for the snow layer
        profile_date=$(grep "ProfileDate" "$backup_file" | awk '{print $3}')
        echo "$profile_date $SNOW_THICK $SNOW_TEMP $VOL_FRAC_I $VOL_FRAC_W $VOL_FRAC_V $VOL_FRAC_S $RHO_S $CONDUC_S $HEATCAP_S $RG $RB $DD $SP $MK $MASS_HOAR $NE $CDOT $METAMO" >> "$sno_file"
        
        count=$((count + 1))
        if (( count % 2000 == 0 )); then
            echo "Processed $count files..."
        fi
    fi
done

echo "Created $count SNO files with 10cm initial snow layer"
